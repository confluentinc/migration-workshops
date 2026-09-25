## Step 1 - Discover and Plan

Before migrating anything, you need a complete inventory of the source cluster. You'll use the KCP CLI on the bastion to discover the Kafka cluster on EC2 — its topics, consumer groups, ACLs, and live broker metrics — and produce `kcp-state.json`, the **single source of truth** that drives every later step.

### Requirements

Complete [Step 0: Setup](../STEP-0-SETUP/README.md) first. The producer and consumer should be running through the Gateway so the scan finds real topics, a consumer group, and traffic.

### How KCP discovers a self-managed cluster

For Amazon MSK, `kcp discover` enumerates clusters through the MSK APIs and reads their metrics from CloudWatch. A Kafka cluster you run on EC2 yourself isn't visible to those APIs, so KCP discovers it directly:

- **Inventory** through the Kafka Admin API, using a credentials file that describes how to reach the cluster: [`kcp/apache-kafka-credentials.yaml`](../kcp/apache-kafka-credentials.yaml).
- **Metrics** by polling a [Jolokia](https://jolokia.org/) agent on each broker, which exposes the broker's JMX metrics over HTTP. The workshop broker runs the agent read-only on port 8778, reachable only from the bastion.

The credentials file already matches the workshop broker:

```yaml
clusters:
  - id: oss-kafka
    bootstrap_servers:
      - kafka.oss-workshop.internal:9092
    auth_method:
      sasl_scram:
        use: true
        username: orders-app
        password: ChangeMe123!
        mechanism: SHA512
        ca_cert: ca.pem
    jolokia:
      endpoints:
        - http://kafka.oss-workshop.internal:8778/jolokia
```

### Scan the cluster

In a third bastion tab (your first two should still be running the producer and consumer), from the workshop root, scan the cluster and poll its metrics for three minutes while your producer and consumer run:

```bash
cd ~/oss-workshop
kcp scan clusters \
  --source-type apache-kafka \
  --credentials-file kcp/apache-kafka-credentials.yaml \
  --state-file kcp-state.json \
  --metrics jolokia \
  --metrics-duration 3m \
  --metrics-interval 10s
```

This records the `orders` topic with its partitions and configs, the `orders-consumer-group` consumer group, any ACLs, and throughput metrics (`BytesInPerSec`, `MessagesInPerSec`, `ClientConnectionCount`, and more) into `kcp-state.json`.

> For a production cluster, poll for 15–30 minutes or longer during representative traffic —
> see [Metrics collection](https://confluentinc.github.io/kcp/0.9.2/apache-kafka-configuration/metrics-collection/).

### Review the results

Generate a metrics report from the state file:

```bash
kcp report metrics --state-file kcp-state.json --source-type apache-kafka
less metric_report_*.md
```

<details>
<summary><b>Optional: Visualize with the KCP UI</b></summary>

KCP includes a local web UI for exploring the state file. It runs on the bastion, and you reach it through an SSH tunnel from your laptop, so this needs your IP in `allowed_ssh_cidrs` (see Step 0).

1. Start the UI on the bastion:
   ```bash
   kcp ui
   ```
2. From your laptop, in the workshop's `terraform` directory, copy the state file and open a tunnel (`-N` keeps the tunnel open without a shell, so the command appears to hang — that's expected; `Ctrl+C` closes it):
   ```bash
   BASTION_IP=$(terraform output -raw bastion_public_ip)
   scp -i ssh.pem ec2-user@"$BASTION_IP":oss-workshop/kcp-state.json .
   ssh -i ssh.pem -L 5556:localhost:5556 -N ec2-user@"$BASTION_IP"
   ```
3. Open http://localhost:5556, upload `kcp-state.json`, and explore the cluster details and metrics.

</details>

### Next Steps

You now have a complete inventory of your source Kafka cluster in `kcp-state.json`. Next you'll use it to provision the Confluent Cloud Enterprise cluster and the private cluster link.

## Topics

**Next topic:** [Step 2: Provision Infrastructure](../STEP-2-PROVISION/README.md)

**Previous topic:** [Step 0: Setup](../STEP-0-SETUP/README.md)
