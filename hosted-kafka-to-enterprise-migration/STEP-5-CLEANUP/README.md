## Step 5 - Cleanup Resources

In this final section, we will safely shut down all workshop resources and clean up the migration environment.

### Cleanup Gateway Resources

Before cleaning up migration infrastructure, remove the Gateway and Kubernetes resources:

1. Stop any running producer/consumer applications:
  ```bash
   pkill -f "orders_producer.py" 2>/dev/null
   pkill -f "orders_consumer.py" 2>/dev/null
  ```
2. Remove Gateway resources:
  ```bash
   kubectl delete gateway workshop-gateway -n confluent 2>/dev/null
   kubectl delete secrets msk-tls cc-tls vault-config scram-admin-credentials plain-jaas -n confluent 2>/dev/null
  ```
3. Stop Vault and uninstall CFK operator:
  ```bash
   pkill -f "vault server" 2>/dev/null
   rm -rf ~/gateway-migration-crs 2>/dev/null
   helm uninstall confluent-operator -n confluent 2>/dev/null
   kubectl delete namespace confluent 2>/dev/null
  ```

> **Note:** k3s and all Kubernetes resources will be automatically destroyed when the bastion host EC2 instance is terminated by Terraform in the final cleanup step.

> **Tip:** You can automate the migration resource cleanup by running `~/clients/cleanup.sh`, which handles all of the steps below including Gateway cleanup. If you prefer to clean up manually, follow the steps below.

### Cleanup Migration Resources

1. Navigate to the `migrate_topics` folder on your bastion host and destroy the Terraform resources.
  ```bash
   cd ~/migrate_topics
   terraform destroy
  ```
   If you enabled any optional migration tracks, expand the matching dropdown(s) **before continuing to step 2**, as those resources must be destroyed before the migration cluster they live in.
  **Optional: Destroy migrated schemas**
   Navigate to the `migrate_schemas` folder on your bastion host and destroy the Terraform resources.
  **Optional: Destroy migrated ACLs**
   Navigate to the `migrate_acls` folder on your bastion host and destroy the Terraform resources.
  **Optional: Destroy migrated connectors**
   Navigate to the `migrate_connectors` folder on your bastion host and destroy the Terraform resources.
2. Navigate to the `migration_infra` folder on your bastion host and destroy the Terraform resources.
  ```bash
   cd ~/migration_infra
   terraform destroy
  ```
   You'll need to enter your Confluent Cloud API Key and API Secret from the [Workshop Introduction](../README.md). Note, this is **not** the Cluster API Key created with the `migration_infra` resources. You'll also need to re-enter the SASL username and password for the MSK cluster.
3. Navigate to the `target_infra` folder on your bastion host and destroy the Terraform resources.
  ```bash
   cd ~/target_infra
   terraform destroy
  ```

### Cleanup MSK Infrastructure

1. **On your local machine**, navigate to the workshop `terraform` directory and destroy the Terraform resources:
  ```bash
   cd path/to/hosted-kafka-to-enterprise-migration/terraform
   terraform destroy
  ```

### Check for Remaining Confluent Cloud Resources

1. Navigate to the [Confluent Cloud Console](https://confluent.cloud) and sign in.
2. Select **Environments**, and if present, select the environment you created for the workshop.
3. Select **Clusters**, and if present, select the cluster you created in the workshop.
4. Navigate to **Cluster Settings** and select **Delete cluster**.
5. Navigate back to your workshop environment, select the **More** dropdown, then select **Delete**.
6. If you enabled any optional migration tracks, expand the matching dropdown(s) to clean up the corresponding Confluent Cloud resources.
  **Optional: Delete migrated connectors**
   Navigate to **Connectors** and delete any connectors you created during the workshop (e.g., the S3 Sink connector).
  **Optional: Delete migrated schemas**
   Navigate to **Schema Registry** and delete any schemas you created during the workshop (e.g., `orders-key` and `orders-value` schemas).
  **Optional: Delete migrated ACLs / service accounts**
   Navigate to **Access Control** and remove any service accounts or role bindings created during the workshop.
7. Open the **right-side menu** in Confluent Cloud and select **API Keys**.
8. Select any **API Keys** related to the workshop environment, and then select the **Delete API key** button.

### Verify AWS Resource Deletion

1. In your AWS account, verify that the `dev-msk-vpc` was deleted.
2. In **Amazon S3**, confirm that your Amazon S3 Bucket beginning with `dev-msk-logs-` was deleted. You may have to empty the bucket in order to delete it.

### Workshop Completion

Congratulations! You have successfully completed the Hosted Kafka to Confluent Cloud Enterprise Migration Workshop. Following the four-step migration framework, you have:

- **Discovered** your source Kafka environment using the KCP CLI
- **Provisioned** target and migration infrastructure with KCP-generated Terraform
- **Migrated data** — topics (plus any optional tracks you enabled: ACLs, schemas, connectors) — using KCP CLI
- **Migrated clients** from MSK to Confluent Cloud with zero downtime using Gateway zero-cut migration
- Cleaned up all workshop resources

## Topics

**Previous topic:** [Step 4: Migrate Clients](../STEP-4-MIGRATE-CLIENTS/README.md)

**Back to:** [Workshop Overview](../README.md)