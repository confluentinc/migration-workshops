## Step 4 - Migrate Clients (Zero-Cut)

In this step, you will perform the actual cutover of client applications from MSK to the new Confluent Cloud Enterprise cluster using KCP's **zero-cut migration**. Because your clients have been connecting through the **Gateway** since Step 0, clients never stop, never reconfigure, and never restart.

The Gateway handles the transition in three phases:
1. **Init** - Validates the entire migration setup without affecting traffic
2. **Fenced** - Briefly blocks traffic (clients see a short retry) while mirror topics are promoted
3. **Switchover** - Routes all traffic to Confluent Cloud; clients resume on their next retry

From the client's perspective, the cutover appears as a brief pause (typically a few seconds) followed by resumed normal operation - now against Confluent Cloud.

### Requirements

Complete [Step 3: Migrate Data](../STEP-3-MIGRATE-DATA/README.md) before starting Step 4.

Ensure the producer and consumer are still running from Step 0 (connected through the Gateway):
```bash
# Check if producer/consumer are running
ps aux | grep orders_producer
ps aux | grep orders_consumer
```

If they are not running, restart them in separate tabs:
```bash
cd ~/clients
source env.gateway
python3 orders_producer.py
```
```bash
cd ~/clients
source env.gateway
python3 orders_consumer.py
```

### Initialize the Migration

The `kcp migration init` command validates the entire migration setup, checking the cluster link health, topic replication status, Gateway configuration, and the fenced/switchover manifests. It does **not** affect live traffic. On success, it prints a `migration-id` that you'll pass to subsequent commands.

```bash
cd ~/
# Make the MSK and Confluent Cloud connection details available
source ~/clients/env.msk
source ~/clients/env.cc
kcp migration init \
  --k8s-namespace confluent \
  --initial-cr-name workshop-gateway \
  --source-bootstrap $MSK_BOOTSTRAP_SERVERS \
  --cluster-bootstrap $CC_BOOTSTRAP_SERVERS \
  --cluster-id $TARGET_CLUSTER_ID \
  --cluster-rest-endpoint $TARGET_REST_ENDPOINT \
  --cluster-link-name $CLUSTER_LINK_NAME \
  --cluster-api-key $CC_API_KEY \
  --cluster-api-secret $CC_API_SECRET \
  --fenced-cr-yaml ~/gateway-migration-crs/gateway-fenced.yaml \
  --switchover-cr-yaml ~/gateway-migration-crs/gateway-switchover.yaml \
  --use-sasl-scram \
  --sasl-scram-username $MSK_SASL_USERNAME \
  --sasl-scram-password $MSK_SASL_PASSWORD
```

Review the output to ensure all pre-flight checks pass. If any checks fail, resolve the issues before proceeding.

Export the migration ID from the output:
```bash
export MIGRATION_ID=<migration-id-from-output>
```

### Check Replication Lag

Before executing the cutover, verify that all mirror topics are fully caught up (zero lag). The `kcp migration lag-check` command displays a live view of per-topic replication lag.

```bash
kcp migration lag-check \
  --rest-endpoint $TARGET_REST_ENDPOINT \
  --cluster-id $TARGET_CLUSTER_ID \
  --cluster-link-name $CLUSTER_LINK_NAME \
  --cluster-api-key $CC_API_KEY \
  --cluster-api-secret $CC_API_SECRET
```

Wait until the lag reaches **zero** for all topics before proceeding. You can run this command multiple times.

### Execute the Zero-Cut Migration

Next, run `migration execute`, a single command that atomically cuts over all client traffic from MSK to Confluent Cloud:

```bash
kcp migration execute \
  --migration-state-file migration-state.json \
  --migration-id $MIGRATION_ID \
  --lag-threshold 1000 \
  --cluster-api-key $CC_API_KEY \
  --cluster-api-secret $CC_API_SECRET \
  --use-sasl-scram \
  --sasl-scram-username $MSK_SASL_USERNAME \
  --sasl-scram-password $MSK_SASL_PASSWORD
```

The command performs four phases automatically:

1. **Pre-flight** - Re-checks replication lag; aborts if lag exceeds the threshold
2. **Block** - Applies the fenced Gateway CR; clients receive `BROKER_NOT_AVAILABLE` and retry automatically
3. **Promote** - Promotes mirror topics one by one (lowest lag first), making them writable on Confluent Cloud
4. **Switch + Unblock** - Applies the switchover Gateway CR; routes traffic to Confluent Cloud, clients resume on their next retry

**Watch your producer and consumer terminals** - you should see output continue without interruption after a brief pause. Consumer offsets are preserved, so there is no data loss or duplication.

### Verify the Migration

1. **Check Gateway status** - confirm the Gateway is now routing to Confluent Cloud:
   ```bash
   kubectl get gateways.platform.confluent.io workshop-gateway -n confluent -o yaml
   ```

2. **Verify producer/consumer** - your running applications should be producing and consuming normally. Check their terminal output to confirm continued operation.

3. **Verify directly on Confluent Cloud** (optional) - you can also verify by connecting directly to Confluent Cloud:
   ```bash
   cd ~/clients
   source env.cc
   python3 kafka_config.py
   ```

### Optional verification tracks

Expand the dropdowns below for the optional tracks you enabled.

<details>
<summary><b>Optional: Verify migrated ACLs</b></summary>

1. Navigate to **Access Control** in the Confluent Cloud Console.

2. Verify that the ACLs from your MSK cluster have been migrated and converted to Confluent Cloud RBAC:
   - Check that service accounts have appropriate permissions
   - Verify topic-level permissions for the `orders` topic
   - Confirm consumer group permissions for `orders-consumer-group`

3. You can also verify ACLs programmatically using the Confluent CLI:
   ```bash
   confluent iam rbac role-binding list --principal User:<service-account-id>
   ```

</details>

<details>
<summary><b>Optional: Verify migrated schemas</b></summary>

1. Navigate to **Schema Registry** in the Confluent Cloud Console.

2. Verify that your schemas have been migrated:
   - Check for `orders-key` schema
   - Check for `orders-value` schema
   - Verify schema versions and compatibility settings

3. You can also list schemas using the Confluent CLI:
   ```bash
   confluent schema-registry subject list
   confluent schema-registry subject describe orders-value
   ```

</details>

<details>
<summary><b>Optional: Verify migrated connectors</b></summary>

1. Navigate to **Connectors** in the Confluent Cloud Console.

2. Verify that your connectors are running:
   - Check the status of your S3 Sink connector (or other migrated connectors)
   - Verify connector tasks are running
   - Check connector metrics and logs

3. You can also check connector status programmatically:
   ```bash
   cd ~/clients
   source env.cc
   export KAFKA_CONNECT_REST_URL="https://<region>.api.confluent.cloud"
   export KAFKA_CONNECT_API_KEY="<YOUR_CONNECT_API_KEY>"
   export KAFKA_CONNECT_API_SECRET="<YOUR_CONNECT_API_SECRET>"
   export KAFKA_CLUSTER_ID="<YOUR_CLUSTER_ID>"
   export ENVIRONMENT_ID="<YOUR_ENVIRONMENT_ID>"

   python3 setup_connector.py cc-status orders-s3-sink
   ```

4. If you set up an S3 Sink connector, verify that data is being written to your S3 bucket:
   ```bash
   aws s3 ls s3://<your-bucket-name>/ --recursive
   ```

</details>

### Next Steps

You have successfully performed a zero-cut migration of your client applications from MSK to Confluent Cloud. Your applications continued running throughout the entire cutover with no downtime, no code changes, and no reconfiguration. Consumer offsets were preserved, ensuring zero data loss. Feel free to take some time to explore your new Confluent Cloud Enterprise Cluster. In the next step, we will safely clean up the workshop resources.

## Topics

**Next topic:** [Step 5: Cleanup Resources](../STEP-5-CLEANUP/README.md)

**Previous topic:** [Step 3: Migrate Data](../STEP-3-MIGRATE-DATA/README.md)
