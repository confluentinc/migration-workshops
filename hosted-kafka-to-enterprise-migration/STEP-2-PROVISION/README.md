## Step 2 - Provision Infrastructure

In this step, you'll use the KCP CLI to generate Terraform configurations for your target and migration infrastructure. KCP generates all the Terraform for you — repeatable, auditable, and no manual resource creation. There are two sub-steps: provisioning the **target infrastructure** (Confluent Cloud environment, cluster, and PrivateLink) and the **migration infrastructure** (cluster linking and networking).

### Requirements

Complete [Step 1: Discover and Plan](../STEP-1-DISCOVER/README.md) before starting Step 2.

### Create the Target Infrastructure

1. Run the following command to create the target infrastructure Terraform:
  ```bash
   kcp create-asset target-infra \
   --state-file kcp-state.json \
   --source-cluster-id $CLUSTER_ARN \
   --needs-environment true \
   --env-name target-env \
   --needs-cluster true \
   --cluster-name target-cluster \
   --cluster-type enterprise \
   --needs-private-link true \
   --subnet-cidrs "10.0.10.0/24","10.0.20.0/24","10.0.30.0/24"
  ```

2. Export the target infrastructure values for use in subsequent steps:
  ```bash
   export TARGET_ENV_ID=$(cd ~/target_infra && terraform output -raw environment_id)
   export TARGET_CLUSTER_ID=$(cd ~/target_infra && terraform output -raw cluster_id)
   export TARGET_REST_ENDPOINT=$(cd ~/target_infra && terraform output -raw cluster_rest_endpoint)
   export CLUSTER_LINK_NAME="msk-to-cc-link"
   terraform output kafka_api_key_id
   terraform output kafka_api_key_secret
   terraform output cluster_bootstrap_endpoint
  ```
   **Make note of the Cluster API key, secret, and bootstrap endpoint. We will use these in the next step.**

### Create the Migration Infrastructure

1. Run the following command to create the migration infrastructure Terraform:
  ```bash
   cd ~/
   kcp create-asset migration-infra \
   --state-file kcp-state.json \
   --source-type msk \
   --cluster-id $CLUSTER_ARN \
   --type 2 \
   --target-environment-id $TARGET_ENV_ID \
   --cluster-link-name $CLUSTER_LINK_NAME \
   --target-cluster-id $TARGET_CLUSTER_ID \
   --target-rest-endpoint $TARGET_REST_ENDPOINT
  ```
2. Navigate to the newly-created `migration-infra` directory and create the infrastructure with terraform:
  ```bash
   cd ~/migration-infra
   terraform init
   terraform apply --auto-approve
  ```

3. When prompted, enter your Confluent Cloud API Key details (if you don't have a Confluent Cloud API Key, see the [Workshop Introduction](../README.md) prerequisites), SASL username ("msk-user") and password ("ChangeMe123!") for the MSK cluster, and Cluster API key. Terraform will begin deploying the necessary resources.
4. After the terraform deployment completes successfully, you can navigate to the [Confluent Cloud Console](https://confluent.cloud/go/cluster) and view your newly-created target resources.

### Configure Confluent Cloud Credentials

Now you need to add the newly-created **credentials** and **Confluent Cloud bootstrap endpoint** to your `env.cc` file. You'll need to log into Confluent Cloud and view the new cluster to get this information.

1. Navigate to your clients directory and update the `env.cc` file with the cluster API credentials:
  ```bash
   cd ~/clients
   nano env.cc
  ```
2. Replace the placeholder values in your `env.cc` file with the actual cluster API credentials from the terraform output:
  ```bash
   # Confluent Cloud Environment Configuration
   export KAFKA_ENV=cc
   export CC_BOOTSTRAP_SERVERS="<BOOTSTRAP_SERVER_ENDPOINT>"
   export CC_API_KEY="<CLUSTER_API_KEY>"
   export CC_API_SECRET="<CLUSTER_API_SECRET>"
  ```

### Configure Gateway for Cutover

Now that the target Confluent Cloud cluster is provisioned and Cluster Linking is active, you need to configure the Gateway for the zero-cut cutover. This script performs several steps automatically:

- Starts **HashiCorp Vault** (dev mode) for secure credential mapping
- Stores the **SCRAM-to-PLAIN credential mappings** so the Gateway can translate client SCRAM credentials to CC API keys after cutover
- Updates the Gateway to the **full init state** with both MSK and CC streaming domains
- **Registers the SCRAM user** with the Gateway via a dedicated registration route
- **Renders the fenced and switchover CRs** to disk for use by `kcp migration` commands in Step 4

1. Run the Gateway target configuration script with your Confluent Cloud credentials:
  ```bash
   cd ~/clients
   ./configure_gateway_target.sh <CC_BOOTSTRAP_SERVERS> <CC_API_KEY> <CC_API_SECRET>
  ```
   Replace the placeholders with the actual values from the terraform output above.
2. Verify the Gateway is configured with both source and target:
  ```bash
   kubectl get gateways.platform.confluent.io -n confluent
   kubectl get secrets -n confluent | grep -E 'msk-tls|cc-tls|vault|scram|plain-jaas'
  ```
3. Verify the rendered migration CRs exist:
  ```bash
   ls ~/gateway-migration-crs/
  ```
   You should see `gateway-fenced.yaml` and `gateway-switchover.yaml`. These will be used by `kcp migration init` and `kcp migration execute` in Step 4.

> **Note:** Your producer and consumer are still running through the Gateway, which continues routing to MSK via passthrough. The Gateway now has both streaming domains configured but will not switch until `kcp migration execute` in Step 4.

### Next Steps

With all infrastructure provisioned — the target Confluent Cloud environment, migration infrastructure with Cluster Linking, and the Gateway configured for cutover — you're ready to begin migrating your data. In the next step, you'll migrate topics from MSK to Confluent Cloud (plus any optional tracks you enabled — ACLs, schemas, connectors).

## Topics

**Next topic:** [Step 3: Migrate Data](../STEP-3-MIGRATE-DATA/README.md)

**Previous topic:** [Step 1: Discover and Plan](../STEP-1-DISCOVER/README.md)