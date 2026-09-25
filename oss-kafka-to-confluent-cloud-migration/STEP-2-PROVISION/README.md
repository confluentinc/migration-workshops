## Step 2 - Provision Infrastructure

In this step you'll use KCP to generate and apply the Terraform for the target **Confluent Cloud Enterprise cluster** and the **private cluster link** from your EC2 broker to it, then configure the Gateway for the cutover. KCP generates all of it: repeatable, auditable, and no manual resource creation.

There are two KCP assets:

- **Target infrastructure** — a Confluent Cloud environment and Enterprise cluster, plus an **ingress** PrivateLink endpoint in your VPC so the bastion (Gateway, KCP, clients) can reach the cluster privately.
- **Migration infrastructure** — an **external outbound cluster link** (KCP type 2). The Enterprise cluster pulls from your broker through AWS PrivateLink: KCP creates an internal NLB and a VPC endpoint service in front of the broker, and a Confluent **egress** access point that connects to it. The broker never gets a public endpoint.

### Requirements

Complete [Step 1: Discover and Plan](../STEP-1-DISCOVER/README.md) first. Run everything below in your KCP tab on the bastion, from the workshop root:

```bash
cd ~/oss-workshop
```

The generated Terraform creates both AWS and Confluent Cloud resources, so export both sets of credentials in this tab (the Cloud resource management API key from the prerequisites):

```bash
export AWS_ACCESS_KEY_ID="<YOUR_AWS_ACCESS_KEY_ID>"
export AWS_SECRET_ACCESS_KEY="<YOUR_AWS_SECRET_ACCESS_KEY>"
export AWS_SESSION_TOKEN="<YOUR_AWS_SESSION_TOKEN>"
export TF_VAR_confluent_cloud_api_key="<YOUR_CLOUD_API_KEY>"
export TF_VAR_confluent_cloud_api_secret="<YOUR_CLOUD_API_SECRET>"
```

### Create the target infrastructure

1. Generate the Terraform for an Enterprise cluster with PrivateLink:
   ```bash
   kcp create-asset target-infra \
     --aws-region "$AWS_REGION" \
     --vpc-id "$VPC_ID" \
     --needs-environment --env-name oss-migration-workshop \
     --needs-cluster --cluster-name target-cluster --cluster-type enterprise \
     --needs-private-link --subnet-cidrs "$PRIVATE_LINK_SUBNET_CIDRS" \
     --prevent-destroy=false
   ```
   `--prevent-destroy=false` keeps the cluster deletable in [Step 5](../STEP-5-CLEANUP/README.md)
   (KCP protects production clusters from `terraform destroy` by default).

2. Apply it:
   ```bash
   terraform -chdir=target_infra init
   terraform -chdir=target_infra apply
   ```
   This creates the environment, the Enterprise cluster, a service account with a cluster API key, the PrivateLink endpoint (in three new subnets), and a Route 53 private zone that points the cluster's hostnames at it. **Billing starts now** — don't forget [Step 5: Cleanup](../STEP-5-CLEANUP/README.md).

3. Save the cluster's IDs, private endpoints and API key to `target.env`, and load it:
   ```bash
   ./kcp/write_target_env.sh
   source target.env
   echo "$TARGET_CLUSTER_ID $TARGET_REST_ENDPOINT $CC_BOOTSTRAP_SERVERS"
   ```
   New bastion shells load `target.env` automatically. It's gitignored — it holds the cluster API key.

### Create the cluster link (migration infrastructure)

1. Generate the Terraform for the external outbound cluster link:
   ```bash
   kcp create-asset migration-infra \
     --state-file kcp-state.json \
     --source-type apache-kafka \
     --cluster-id oss-kafka \
     --cc-type commercial \
     --type 2 \
     --region "$AWS_REGION" \
     --vpc-id "$VPC_ID" \
     --subnet-id "$KAFKA_BROKER_SUBNET_ID" \
     --security-group-id "$LINK_PROVISIONER_SG_ID" \
     --target-environment-id "$TARGET_ENV_ID" \
     --target-cluster-id "$TARGET_CLUSTER_ID" \
     --target-rest-endpoint "$TARGET_REST_ENDPOINT" \
     --target-cluster-type enterprise \
     --cluster-link-name "$CLUSTER_LINK_NAME"
   ```
   The link can only be created through the Enterprise cluster's private REST endpoint, so the generated Terraform launches a small EC2 instance in the broker's subnet (`--subnet-id`, `--security-group-id`) that makes that call once at boot.

2. Fill in the details KCP can't know about a self-managed broker:
   ```bash
   ./kcp/prepare_migration_infra.sh
   ```
   This does two things (see the comments in
   [`kcp/prepare_migration_infra.sh`](../kcp/prepare_migration_infra.sh)):
   - Writes `migration-infra/workshop-brokers.auto.tfvars` with the broker's subnet and private IP. KCP reads those from the MSK API for MSK sources; for Apache Kafka it leaves them blank.
   - Adds these settings to the cluster link KCP creates:

     | Setting | Why |
     | :-- | :-- |
     | `ssl.truststore.type=PEM`, `ssl.truststore.certificates=<workshop CA>` | The broker's certificate comes from the workshop CA, not a public CA as on MSK, so the link needs the CA to verify it. |
     | `consumer.offset.sync.enable=true` | Copies committed consumer offsets to Confluent Cloud, so the consumer resumes at its position after the cutover. |
     | `consumer.offset.group.filters` → `orders-consumer-group` | Names the groups to sync. Without a filter, offset sync syncs **no** groups, and the consumer would restart from `auto.offset.reset` — reprocessing or skipping orders. |
     | `consumer.offset.sync.ms=5000` | Syncs every 5 seconds instead of every 30, so the cutover in Step 4 only has to wait a few seconds for the consumer's final offsets. |

3. Apply it:
   ```bash
   terraform -chdir=migration-infra init
   terraform -chdir=migration-infra apply
   ```
   This creates the NLB and VPC endpoint service in front of the broker, the Confluent egress gateway, access point and DNS record for `kafka.oss-workshop.internal`, and the link-provisioning instance.

4. Verify the link. The provisioning instance creates it a minute or two after `apply`
   finishes:
   ```bash
   ./kcp/cc_status.sh link
   ./kcp/cc_status.sh configs
   ```
   `link` should show `"link_state": "ACTIVE"` and `"link_error": "NO_ERROR"`. `configs` should list `security.protocol=SASL_SSL`, `ssl.truststore.type=PEM`, and the three `consumer.offset.*` settings.

   > **If the link doesn't appear:** `cc_status.sh link` returns a 404 until it exists. Wait
   > another minute. If it still doesn't exist, the provisioning instance's one attempt failed.
   > Send the same request yourself as a dry run, which prints Confluent Cloud's reason:
   > ```bash
   > ./kcp/create_link.sh --validate-only
   > ```
   > Fix what it reports, then create the link by re-running KCP's provisioning instance
   > (`terraform -chdir=migration-infra apply -replace=module.external_outbound_cluster_link.aws_instance.external_outbound_cluster_link`)
   > or directly with `./kcp/create_link.sh`.

### Configure the Gateway for cutover

Now point the Gateway at the Enterprise cluster (in addition to the source) and prepare the cutover. This script starts Vault, stores the SCRAM→API key credential mapping, creates the Gateway's secrets, updates the Gateway to its init state, registers the SCRAM user, and renders the switchover CR:

```bash
./gateway/configure_gateway_target.sh
```

Verify the switchover CR exists (the migration manifest points at it in Step 4):

```bash
ls gateway/rendered-crs/   # gateway-switchover.yaml
```

There is no fenced CR to prepare: at cutover KCP fences `migration-route` by patching the live Gateway itself.

> Your producer and consumer keep running through the Gateway the whole time — it continues
> routing to the source broker until `kcp migration execute` in Step 4.

### Next Steps

The Enterprise cluster and the private cluster link exist, and the Gateway knows about both clusters. Next you'll create the mirror topics and replicate your data.

## Topics

**Next topic:** [Step 3: Migrate Data](../STEP-3-MIGRATE-DATA/README.md)

**Previous topic:** [Step 1: Discover and Plan](../STEP-1-DISCOVER/README.md)
