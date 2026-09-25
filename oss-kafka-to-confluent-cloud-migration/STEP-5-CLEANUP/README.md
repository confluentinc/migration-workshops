## Step 5 - Cleanup Resources

Tear down everything you created. **The Enterprise cluster, the PrivateLink endpoints, the NAT gateway, the NLB and the EC2 instances all bill hourly, so do this as soon as you finish.**

Cleanup runs in two places, in this order:

1. **On the bastion** — the Gateway and the KCP-generated Terraform (mirror topics, cluster link path, Enterprise cluster). These resources live inside your VPC, so they must go first.
2. **On your laptop** — the AWS source environment (`terraform/`), including the bastion itself.

### 1. Clean up from the bastion

In a bastion tab, export the same credentials you used in Step 2, then run the cleanup script from the workshop root:

```bash
cd ~/oss-workshop
export AWS_ACCESS_KEY_ID="<YOUR_AWS_ACCESS_KEY_ID>"
export AWS_SECRET_ACCESS_KEY="<YOUR_AWS_SECRET_ACCESS_KEY>"
export AWS_SESSION_TOKEN="<YOUR_AWS_SESSION_TOKEN>"
export TF_VAR_confluent_cloud_api_key="<YOUR_CLOUD_API_KEY>"
export TF_VAR_confluent_cloud_api_secret="<YOUR_CLOUD_API_SECRET>"
./cleanup.sh
```

It will:
1. Stop the producer/consumer
2. Remove the Gateway, the CFK operator and Vault
3. Destroy the mirror topics (`migrate_topics/`)
4. Destroy the cluster link path (`migration-infra/`): NLB, VPC endpoint service, Confluent
   egress gateway and access point, and the link-provisioning instance
5. Destroy the Enterprise cluster, environment and PrivateLink endpoint (`target_infra/`)

It exits non-zero, with a warning, if any of the billable resources in steps 4–5 remain. It's safe to re-run.

<details>
<summary><b>Manual cleanup (if you prefer, or if a step fails)</b></summary>

```bash
pkill -f orders_producer.py; pkill -f orders_consumer.py
kubectl delete gateways.platform.confluent.io workshop-gateway -n confluent
helm uninstall confluent-operator -n confluent
pkill -f "vault server"
terraform -chdir=migrate_topics destroy
terraform -chdir=migration-infra destroy
terraform -chdir=target_infra destroy
```

</details>

### 2. Destroy the source environment from your laptop

Only after the bastion cleanup succeeds (the VPC can't be deleted while KCP's subnets, endpoints and NLB are still in it), from the workshop directory on your laptop with your AWS credentials exported:

```bash
cd migration-workshops/oss-kafka-to-confluent-cloud-migration/terraform
terraform destroy
```

This removes the bastion, the Kafka broker, the NAT gateway, the private DNS zone and the VPC.

### Verify

1. In the [Confluent Cloud Console](https://confluent.cloud), confirm the `oss-migration-workshop` environment is gone. Under **API keys**, delete any keys you created for the workshop that you no longer need.
2. In the AWS Console, confirm the `oss-migration-vpc` VPC is gone.

### Workshop Completion

Congratulations! Following the six-stage framework, you have:

- **Discovered** a self-managed open-source Kafka cluster on EC2 with the KCP CLI — its inventory through the Kafka Admin API and its metrics through Jolokia
- **Provisioned** a Confluent Cloud Enterprise cluster and a private, external outbound cluster link with KCP-generated Terraform — no public endpoints, no tunnels
- **Migrated data** via Cluster Linking over AWS PrivateLink
- **Migrated clients** from OSS Kafka to Confluent Cloud with zero downtime via the Gateway
- **Cleaned up** all AWS and Confluent Cloud resources

## Topics

**Previous topic:** [Step 4: Migrate Clients](../STEP-4-MIGRATE-CLIENTS/README.md)

**Back to:** [Workshop Overview](../README.md)
