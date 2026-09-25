## Step 3 - Migrate Data

Now you'll create **mirror topics** on the cluster link so your `orders` data replicates from the broker on EC2 to the Enterprise cluster. KCP generates the Terraform; you apply it.

### Requirements

Complete [Step 2: Provision Infrastructure](../STEP-2-PROVISION/README.md) first. In your tab on the bastion, confirm the Step 2 values are loaded:

```bash
cd ~/oss-workshop
echo "$TARGET_CLUSTER_ID $TARGET_REST_ENDPOINT $CLUSTER_LINK_NAME"
```

If any are empty, run `source target.env`. `TF_VAR_confluent_cloud_api_key` and `TF_VAR_confluent_cloud_api_secret` must still be exported (re-export them if this is a new tab).

> Your producer and consumer keep running through the Gateway during this step — there is zero
> disruption while data replicates.

### Create the mirror topics

1. Generate the mirror-topics Terraform:
   ```bash
   kcp create-asset migrate-topics \
     --source-type apache-kafka \
     --cc-type commercial \
     --state-file kcp-state.json \
     --cluster-id oss-kafka \
     --mode mirror \
     --topics-include orders \
     --target-cluster-id "$TARGET_CLUSTER_ID" \
     --target-rest-endpoint "$TARGET_REST_ENDPOINT" \
     --cluster-link-name "$CLUSTER_LINK_NAME"
   ```

2. Apply it:
   ```bash
   terraform -chdir=migrate_topics init
   terraform -chdir=migrate_topics apply
   ```
   This creates a read-only mirror of `orders` on the Enterprise cluster and begins replication. The Terraform talks to the cluster's private REST endpoint, which is why it runs on the bastion.

### Verify replication

1. Check the mirror topic and its lag:
   ```bash
   ./kcp/cc_status.sh mirrors
   ```
   `orders` should be `ACTIVE`, with its maximum partition lag falling toward zero.

2. Check that consumer offsets are syncing. Once the consumer has committed on the source and the link's offset sync has run (every 5 seconds), `orders-consumer-group` appears on the destination:
   ```bash
   ./kcp/cc_status.sh groups
   ```

3. Read the mirrored data directly from Confluent Cloud. Use a **different consumer group**, so this reader doesn't disturb the synced offsets of `orders-consumer-group`:
   ```bash
   cd clients
   source .venv/bin/activate
   source env.cc
   python3 orders_consumer.py --group-id mirror-check
   ```
   You should see the orders your producer has sent, read from Confluent Cloud over PrivateLink. Press `Ctrl+C` to stop, then `cd ..`.

> **Confluent Cloud Console:** the cluster, the cluster link and the mirror topic appear in the
> Console, but browsing messages there requires your browser to have network access to the
> private cluster — which is why this step reads the data from the bastion instead.

### Next Steps

Your data is replicating to Confluent Cloud via Cluster Linking, while your clients keep running against the source broker through the Gateway. Next you'll execute the zero-cut cutover.

## Topics

**Next topic:** [Step 4: Migrate Clients](../STEP-4-MIGRATE-CLIENTS/README.md)

**Previous topic:** [Step 2: Provision Infrastructure](../STEP-2-PROVISION/README.md)
