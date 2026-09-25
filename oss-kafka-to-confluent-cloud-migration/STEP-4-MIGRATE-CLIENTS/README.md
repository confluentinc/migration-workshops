## Step 4 - Migrate Clients (Zero-Cut)

Now you'll cut your client applications over from the source broker to the Enterprise cluster using KCP's **zero-cut migration**. Because your clients have connected through the **Gateway** since Step 0, they never stop, reconfigure, or restart.

KCP drives the cutover as a resumable state machine:
1. **Init** — validates the whole setup without touching traffic
2. **Fence** — briefly blocks client traffic at the Gateway (clients see a short retry)
3. **Promote** — once the mirrors have caught up, makes them regular, writable topics
4. **Switchover** — routes all traffic to Confluent Cloud; clients resume on their next retry

### Requirements

Complete [Step 3: Migrate Data](../STEP-3-MIGRATE-DATA/README.md) first. The producer and consumer should still be running through the Gateway (`source env.gateway`). Run the commands below in your KCP tab on the bastion, from the workshop root:

```bash
cd ~/oss-workshop
echo "$KAFKA_BOOTSTRAP $CC_BOOTSTRAP_SERVERS $TARGET_CLUSTER_ID"
```

If the Confluent Cloud values are empty, run `source target.env`.

### The migration manifest

KCP describes a migration in one declarative file, and every `kcp migration` command reads it: [`kcp/gateway-migration.yaml`](../kcp/gateway-migration.yaml). It names:

- the **source** (`$KAFKA_BOOTSTRAP`, SCRAM-SHA-512, verified against the workshop CA) and the **target** Enterprise cluster (its private bootstrap and REST endpoints, and API key);
- the **cluster link** — and asks KCP to pause its consumer-offset sync during the cutover, after a 10-second drain so the consumer's final offsets reach Confluent Cloud;
- the **Gateway**: the live `workshop-gateway` CR, the `migration-route` to fence (KCP patches the fence onto the live CR itself), and the switchover CR you rendered in Step 2.

It holds no secrets. Every value is a `${VAR}` reference to `workshop.env` or `target.env` (`interpolate: true`), and KCP stops with an error naming any variable that isn't set.

### Initialize the migration

`kcp migration init` validates the Gateway CRs against each other (including that every secret the switchover CR references exists), the cluster link and its mirror topics, and that the link has consumer-offset sync enabled. It does **not** affect live traffic.

```bash
kcp migration init --migration-yaml kcp/gateway-migration.yaml
```

It registers the migration as `oss-to-cc` (the manifest's `metadata.name`) in `migration-state.json`. If a check fails, fix the cause and re-run `init` — it updates the same migration.

### Check replication lag

Watch the mirror topics catch up (near-zero lag) before cutting over. This opens a live view; press `q` to quit:

```bash
kcp migration lag-check --migration-yaml kcp/gateway-migration.yaml
```

### Execute the zero-cut migration

```bash
kcp migration execute \
  --migration-yaml kcp/gateway-migration.yaml \
  --migration-state-file migration-state.json
```

This runs the cutover end to end:

1. **Check lags** — waits until total mirror lag is under `lagThreshold` (1000) so the fence
   stays short.
2. **Fence** — patches a fence onto `migration-route`; clients get `BROKER_NOT_AVAILABLE` and
   retry. The SCRAM registration route stays open.
3. **Drain and pause offset sync** — waits 10 seconds so the link copies the consumer's final
   offsets, then pauses offset sync.
4. **Promote** — promotes the mirror topics at zero lag.
5. **Switch** — applies the switchover CR: traffic now goes to Confluent Cloud, and the Gateway
   swaps client SCRAM credentials for the cluster API key. KCP then restores offset sync.

**Watch your producer and consumer tabs** — after a brief pause they continue without interruption, now against Confluent Cloud. Cluster Linking mirrored records byte-for-byte and synced the `orders-consumer-group` offsets, so the consumer resumes from its committed position rather than reprocessing the whole topic.

> **On the "no loss or duplication" guarantee:** record *bytes* and committed *offsets* are
> preserved by Cluster Linking. The producer, though, is **at-least-once** — during the brief
> fenced window a send can fail, and it retries the *same* order (see the producer note below),
> so a record that was persisted but not acknowledged may be delivered twice. Treat end-to-end
> "no loss or duplication" as something to **measure**, not assume: compare the producer's
> delivered `order_id`s (printed in its shutdown summary) against what the consumer reads on
> Confluent Cloud.

### Verify the migration

1. Confirm the Gateway now routes only to Confluent Cloud:
   ```bash
   kubectl get gateways.platform.confluent.io workshop-gateway -n confluent -o yaml | grep -A3 streamingDomains
   ```

2. Confirm the mirror topic was promoted — it reports `STOPPED`, meaning it is now a regular, writable topic that no longer mirrors the source:
   ```bash
   ./kcp/cc_status.sh mirrors
   kcp migration list
   ```

3. Optionally read directly from Confluent Cloud and compare against the producer's delivered `order_id`s (use a separate group so you don't move `orders-consumer-group`):
   ```bash
   cd clients
   source .venv/bin/activate
   source env.cc
   python3 orders_consumer.py --group-id cutover-check
   ```

> **Producer note (at-least-once).** On a failed send the producer keeps the order and retries
> the **same** one on the next loop, so orders are never silently skipped; the trade-off is a
> possible duplicate if the failure happened after the broker persisted the record. On shutdown
> it prints a delivery summary (delivered count, last delivered `order_id`, any undelivered
> order) so you can reconcile against the consumer.

### Recovery from an interrupted cutover

If `kcp migration execute` is interrupted partway (Ctrl+C, a dropped browser session), the Gateway can be left **fenced**, so clients keep receiving `BROKER_NOT_AVAILABLE`. To recover:

1. See where the migration stopped:
   ```bash
   kcp migration list
   ```
2. Re-run the same `kcp migration execute` command. It resumes from the last completed step — re-applying the fence first if one was in place — and finishes the switchover.
3. If you can't proceed and need clients unblocked, put the Gateway back in its init state, which routes clients to the source broker. Do this **only before the mirror topics are promoted** (`kcp migration list` shows the migration short of `promoted`): mirroring is still running then, so nothing is lost, and re-running `execute` later fences again before it promotes anything. Once the mirrors are promoted the source no longer replicates to Confluent Cloud, and the way out is forward — re-run `execute` to finish the switchover.
   ```bash
   sed -e "s#__OSS_BOOTSTRAP__#${KAFKA_BOOTSTRAP}#g" \
       -e "s#__CC_BOOTSTRAP_SERVERS__#${CC_BOOTSTRAP_SERVERS}#g" \
     gateway/gateway-manifests/gateway-init.yaml | kubectl apply -f -
   ```

### Next Steps

You've migrated your clients from open-source Kafka to a Confluent Cloud Enterprise cluster with zero downtime, no code changes, and preserved offsets. Finally, tear everything down.

## Topics

**Next topic:** [Step 5: Cleanup Resources](../STEP-5-CLEANUP/README.md)

**Previous topic:** [Step 3: Migrate Data](../STEP-3-MIGRATE-DATA/README.md)
