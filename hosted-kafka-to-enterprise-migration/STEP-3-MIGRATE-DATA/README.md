## Step 3 - Migrate Data

In this step, you'll migrate your Kafka topics from MSK to Confluent Cloud. **ACLs, schemas, and connectors are optional tracks** — at the end of this step, follow only the dropdown sections for the tracks you enabled at deploy time. Each resource type follows the same pattern:

- **Topics** (required), plus **Schemas and ACLs** (optional): KCP CLI generates Terraform assets, then you apply them ("generate then apply").
- **Connectors** (optional): recreated as fully-managed connectors through the Confluent Cloud Console.

### Requirements

Complete [Step 2: Provision Infrastructure](../STEP-2-PROVISION/README.md) before starting Step 3. Ensure you have configured your `env.cc` file with the Confluent Cloud credentials from the previous step.

Verify that the environment variables from previous steps are still set:

```bash
echo $CLUSTER_ARN $TARGET_CLUSTER_ID $TARGET_REST_ENDPOINT $CLUSTER_LINK_NAME
```

If any are empty, re-export them from the target_infra terraform outputs (see [Step 2](../STEP-2-PROVISION/README.md)).

> **Note:** Your producer and consumer applications are still running through the Gateway, which continues routing traffic to MSK. There is zero disruption to running clients during data migration.

### Create the Mirror Topics

1. Run the following command to create the mirror topics. Source `env.cc` first so the generated Terraform picks up your Confluent Cloud credentials:
  ```bash
   source ~/clients/env.cc
   cd ~/
   kcp create-asset migrate-topics \
   --state-file kcp-state.json \
   --cluster-id $CLUSTER_ARN \
   --mode mirror \
   --target-cluster-id $TARGET_CLUSTER_ID \
   --target-rest-endpoint $TARGET_REST_ENDPOINT \
   --cluster-link-name $CLUSTER_LINK_NAME
  ```
   This creates mirror topics on your cluster link and begins data replication for migration.

2. Navigate to the new `migrate_topics` folder:
  ```bash
   cd migrate_topics
   terraform init
   terraform apply --auto-approve
  ```

3. You can now navigate to the **Topics** menu inside your cluster in Confluent Cloud and view your orders topic.

   You may notice that topic information is currently limited for this privately-networked Enterprise Cluster. If you want to view more topic-specific details, you can use the Windows bastion host in the optional section below for a more granular view.

<details>
<summary><b>Optional: View Messages in Confluent Cloud Topics UI</b></summary>

Because the Enterprise cluster is private, to view messages in the Topics UI you need to access the Topics UI via a Windows bastion host. Please perform the following steps from your laptop — **not directly on the bastion host**.

1. Get the Windows bastion host details from the `terraform` directory **on your laptop**:
  ```bash
   cd path/to/hosted-kafka-to-enterprise-migration/terraform
   terraform output windows_bastion_ip
   terraform output windows_bastion_password
   terraform output windows_bastion_username
  ```
2. RDP to the Source (AWS) Bastion Host.
3. In the [Topics UI](https://confluent.cloud/go/topics), select the destination environment and cluster.
4. Verify mirrored topics appear in your Enterprise cluster.
  Verify Screenshot

</details>


### Optional migration tracks

Follow only the dropdowns for the tracks you enabled at deploy time. Each runs against resources that exist only if you opted in to the corresponding feature.

<details>
<summary><b>Optional: Migrate ACLs</b></summary>

In [Step 1](../STEP-1-DISCOVER/README.md), KCP discovered the ACLs from your MSK cluster. Now you'll use the KCP CLI to generate Terraform that migrates these ACLs to Confluent Cloud RBAC (Role-Based Access Control).

1. **Generate ACL migration Terraform**:
  ```bash
   cd ~/
   kcp create-asset migrate-acls kafka \
   --state-file kcp-state.json \
   --cluster-id $CLUSTER_ARN \
   --target-cluster-id $TARGET_CLUSTER_ID \
   --target-rest-endpoint $TARGET_REST_ENDPOINT
  ```
2. **Apply the generated Terraform**:
  ```bash
   cd ~/msk-migration-cluster_kafka_acls
   terraform init
   terraform apply --auto-approve
  ```
  <details>
  <summary><b>Optional: UI steps</b></summary>

   You can create equivalent RBAC role bindings manually in the Confluent Cloud Console instead.
  1. In the Console, open **Accounts & access** → **Service accounts**, and create a service account for each principal that had ACLs on MSK.
  2. For each service account, open **Access** → **Add role binding** and map the source ACL to a Confluent Cloud RBAC role — for example, `DeveloperRead`/`DeveloperWrite` scoped to the `orders` topic, and `DeveloperRead` scoped to the `orders-consumer-group` consumer group.
  3. Confirm the new bindings appear under **Accounts & access** → **Role bindings** for the target cluster.
  </details>
3. **Verify migrated ACLs**:
  - Navigate to **Access Control** in the Confluent Cloud Console
  - Verify that service accounts have been created and role bindings have been applied
  - Check that topic-level and consumer group permissions match your source ACLs

> **Alternative: Migrate ACLs using KCP UI** — You can also migrate ACLs through the [KCP UI](http://localhost:5556) (the same local UI from [Step 1](../STEP-1-DISCOVER/README.md), reached over the SSH tunnel). Open it, select your migration project, navigate to the **ACLs** section, review the discovered ACLs and their RBAC mappings, then click **Migrate ACLs** to apply them. This provides a visual interface to review the mapping between source ACLs and target RBAC before executing.

</details>



<details>
<summary><b>Optional: Migrate Schemas</b></summary>

In [Step 1](../STEP-1-DISCOVER/README.md), KCP discovered the `orders-key` and `orders-value` schemas from the AWS Glue Schema Registry. Now you'll use the KCP CLI to generate Terraform that migrates these schemas to Confluent Cloud Schema Registry.

1. **Scan the Glue Schema Registry into the state file.** The Glue registry is separate from the cluster scan in [Step 1](../STEP-1-DISCOVER/README.md), so `kcp create-asset migrate-schemas` will not find it until you scan it explicitly:
  ```bash
   cd ~/
   kcp scan schema-registry --sr-type glue --state-file kcp-state.json \
   --region us-west-2 --registry-name dev-msk-schemas
  ```
2. **Get your Confluent Cloud Schema Registry REST endpoint**:
  ```bash
   confluent schema-registry cluster describe -o json | jq -r '.endpoint_url'
  ```
   It looks like `https://psrc-xxxxx.<region>.aws.confluent.cloud`.
3. **Generate schema migration Terraform**. Pass the Glue registry name, its AWS region, and the Confluent Cloud SR endpoint from the previous step:
  ```bash
   cd ~/
   kcp create-asset migrate-schemas \
   --state-file kcp-state.json \
   --glue-registry dev-msk-schemas \
   --region us-west-2 \
   --cc-sr-rest-endpoint <CC_SR_REST_ENDPOINT>
  ```
4. **Create a Schema Registry API key** so Terraform can authenticate to the target Schema Registry. This is a *Schema Registry-scoped* key — not your Cloud API key or a Kafka cluster key.
  ```bash
   confluent schema-registry cluster describe -o json | jq -r '.cluster'

   confluent api-key create --resource <lsrc-xxxxx> -o json
  ```
   Export the returned key/secret (plus the endpoint) so the Confluent Terraform provider picks them up:
   Verify the key works before applying (should return `[]` or a list of subjects, not `401`):
5. **Apply the generated Terraform**:
  ```bash
   cd ~/migrate_schemas
   terraform init
   terraform apply
  ```
  <details>
  <summary><b>Optional: UI steps</b></summary>

   You can register the schemas manually in the Confluent Cloud Schema Registry UI instead.
  1. In the Confluent Cloud Console, select your target environment, then open **Schema Registry** → **Schemas**.
  2. Click **Add schema**. Set the subject name to `orders-key`, choose the schema type that matches the source (e.g., **Avro**), and paste the schema body exported from AWS Glue Schema Registry.
  3. Repeat for the `orders-value` subject.
  4. For each subject, open **Compatibility** and set the compatibility mode to match the source registry.
  </details>
6. **Verify migrated schemas**:
  - Navigate to **Schema Registry** in the Confluent Cloud Console
  - Verify that schemas for `orders-key` and `orders-value` are present
  - Check schema versions and compatibility settings
   You can also verify using the script:

</details>



<details>
<summary><b>Optional: Migrate Connectors</b></summary>

In [Step 0](../STEP-0-SETUP/README.md), you verified that an S3 Sink connector (`dev-orders-s3-sink`) is running on MSK Connect. Now you'll recreate it as a fully-managed connector in Confluent Cloud through the Confluent Cloud Console.

> **Note:** KCP v0.8.2 removed MSK Connect scanning, so `kcp discover` no longer captures connectors in `kcp-state.json` and `kcp create-asset migrate-connectors msk` finds nothing to migrate. Deploy the fully-managed connector through the Console instead.

1. **Deploy the fully-managed S3 Sink connector**:
  1. From the target cluster overview in the Confluent Cloud Console, open **Connectors** → **Add connector**.
  2. Search for and select the **Amazon S3 Sink** connector.
  3. Name the connector `orders-s3-sink`.
  4. Configure the connector: select the `orders` topic, supply the S3 bucket name (same as the source), provide AWS credentials with write access, and match the input/output formats from the source MSK Connect configuration.
  5. Launch the connector and wait for its status to reach **Running**.
2. **Verify migrated connector**:
  - Navigate to **Connectors** in the Confluent Cloud Console
  - Verify that the `orders-s3-sink` connector is running
  - Check connector metrics and logs
   You can also verify the connector using the CLI:

</details>



### Next Steps

You've migrated your Kafka topics from MSK to Confluent Cloud (plus any optional tracks you enabled — ACLs, schemas, connectors). Data is actively replicating via Cluster Linking. Your producer and consumer have been running uninterrupted through the Gateway this entire time. In the next step, you'll execute the zero-cut migration to seamlessly redirect all client traffic to Confluent Cloud.

## Topics

**Next topic:** [Step 4: Migrate Clients](../STEP-4-MIGRATE-CLIENTS/README.md)

**Previous topic:** [Step 2: Provision Infrastructure](../STEP-2-PROVISION/README.md)