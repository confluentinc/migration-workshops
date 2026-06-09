## Step 0 - Setup

Before beginning the migration, set up access to the migration environment, deploy the migration Gateway, and verify your source Kafka applications are running correctly.

### Requirements

Before starting this lab, ensure you have:

1. Completed all prerequisites from the [Workshop Introduction](../README.md).
2. **Deployed the top-level Terraform infrastructure** that creates the MSK cluster, VPC, and bastion host

### Access the Bastion Host

How you migrate to Confluent Cloud is dependent on whether your source cluster uses **public** or **private** endpoints. For **public** cluster migrations, you can simply run the KCP CLI directly on your local machine. For **private** clusters, however, you need to temporarily deploy a **bastion host** for the KCP CLI to have access to the cluster. Since **private** clusters are the most common in real-world production scenarios, we will use this approach for the workshop.

The bastion host will serve as the migration control plane for moving data from MSK to Confluent Cloud. It will:
- Host the migration tools, scripts, and Gateway proxy
- Provide secure access to both MSK and Confluent Cloud
- Execute the migration commands and monitor progress
- For the workshop only (not production environments), will host our producer and consumer applications

#### Instructions

1. Navigate to the [AWS EC2 Console](https://us-west-2.console.aws.amazon.com/ec2/home?region=us-west-2#Instances:instanceState=running) and click the instance ID for the `dev-migration-bastion-host` instance.

2. Select the **Connect** button.

3. Leave all default selections, and choose **Connect**. This opens a connection to your EC2 instance in the browser.

### Set Up Client Applications

Now that you've accessed the bastion host, you'll set up the client applications and configure the MSK environment variables.

#### Configure Environment Variables
1. Copy the workshop client resources to your home directory:

   ```bash
   cp -r migration-workshops/hosted-kafka-to-enterprise-migration/clients ~/
   cd ~/clients
   ```

2. Update the `env.msk` file with your MSK cluster configuration:
   ```bash
   nano env.msk
   ```

3. Set `MSK_BOOTSTRAP_SERVERS` to your MSK cluster bootstrap servers (from the Terraform output). The username and password are pre-populated with the workshop defaults.

4. Source the environment file:
   ```bash
   source env.msk
   ```

#### Run Setup Script
1. Run the setup script and test the configuration:
   ```bash
   ./setup.sh
   python3 kafka_config.py
   ```

### Deploy the Migration Gateway

In this workshop, you'll use **Confluent Cloud Gateway** to enable a **zero-cut migration** -- your client applications will connect through the Gateway from the start, and during the cutover in Step 4, traffic will be seamlessly redirected to Confluent Cloud without stopping or reconfiguring any clients.

The Gateway runs on a lightweight Kubernetes (k3s) instance that was pre-installed on the bastion host during Terraform provisioning. It is deployed via Confluent for Kubernetes (CFK) using the `Gateway` CRD.

In this step, you'll deploy the Gateway in **passthrough mode** — client SCRAM-SHA-512 credentials flow directly through to MSK. During the cutover in Step 4, KCP will automatically switch the Gateway to **swap mode**, where it maps client SCRAM credentials to Confluent Cloud SASL/PLAIN credentials.

1. Verify Kubernetes is running:
   ```bash
   kubectl cluster-info
   ```

2. Deploy the Gateway (this installs CFK, creates TLS truststores, and deploys a Gateway routing to MSK):
   ```bash
   cd ~/clients
   source env.msk
   ./setup_gateway.sh
   ```

3. Verify the Gateway is running:
   ```bash
   kubectl get pods -n confluent
   kubectl get gateways.platform.confluent.io -n confluent
   ```

   > **Note:** Use the fully-qualified resource name `gateways.platform.confluent.io`. The bare `kubectl get gateway` resolves to the Kubernetes Gateway API CRD (`gateways.gateway.networking.k8s.io`) that k3s/Traefik registers, which is empty — so it returns "No resources found in confluent namespace" even though the Confluent Gateway exists.

4. Source the Gateway environment for your client applications:
   ```bash
   source env.gateway
   ```

   From this point forward, the producer and consumer will connect through the Gateway using SCRAM-SHA-512, which transparently proxies traffic to MSK.

### Test the Producer Application

1. Execute the orders producer application to send test messages:
   ```bash
   python3 orders_producer.py
   ```
2. Verify that messages are being sent successfully. The producer is connecting through the Gateway, which routes to MSK. **Leave the producer running** in this tab.

### Test the Consumer Application
1. In a **second tab**, connect to the EC2 instance following the steps above. Then, execute the orders consumer application:
   ```bash
   cd ~/clients
   source env.gateway
   python3 orders_consumer.py
   ```
2. Verify that messages are being consumed correctly. Like the producer, the consumer connects through the Gateway. **Leave the consumer running** in this tab.

### Optional migration tracks

If you enabled any optional tracks at deploy time (ACLs, Schemas, Connectors), expand the matching section below and follow the steps. Skip this entire section if you only chose the core topic migration.

<details>
<summary><span style="font-size: 1.17em; font-weight: 700;">Optional: Set up ACLs (for ACL migration track)</span></summary>

ACLs control who can access which topics, consumer groups, and other Kafka resources. In this step, you'll create ACLs on your MSK cluster for the orders topic and consumer group.

> **Note:** Open a **third tab** and connect to the bastion host. The remaining setup steps require direct MSK access:
> ```bash
> cd ~/clients
> source env.msk
> ```

1. Run the ACL setup script to create ACLs on your MSK cluster:
   ```bash
   python3 setup_acls.py
   ```

2. Verify the ACLs were created:
   ```bash
   python3 setup_acls.py list
   ```

   These ACLs will be migrated to Confluent Cloud RBAC in [Step 3: Migrate Data](../STEP-3-MIGRATE-DATA/README.md).

</details>
</br>
<details>
<summary><span style="font-size: 1.17em; font-weight: 700;">Optional: Verify schemas in Glue Schema Registry (for Schema migration track)</span></summary>

Schemas define the structure of your data and enable schema evolution. The Terraform deployment created an AWS Glue Schema Registry with Avro schemas for the orders topic.

1. The `glue-list` command queries AWS Glue directly, so it needs AWS credentials. Paste your AWS role credentials first (use your own values for `<YOUR_AWS_ACCESS_KEY_ID>`, `<YOUR_AWS_SECRET_ACCESS_KEY>`, and `<YOUR_AWS_SESSION_TOKEN>`):
   ```bash
   export AWS_ACCESS_KEY_ID="<YOUR_AWS_ACCESS_KEY_ID>"
   export AWS_SECRET_ACCESS_KEY="<YOUR_AWS_SECRET_ACCESS_KEY>"
   export AWS_SESSION_TOKEN="<YOUR_AWS_SESSION_TOKEN>"
   ```

2. List the schemas in the Glue Schema Registry:
   ```bash
   python3 setup_schemas.py glue-list
   ```

   You should see two schemas:
   - **orders-key**: Avro key schema (integer order_id)
   - **orders-value**: Avro value schema (Order record with fields like customer_id, product_id, total_amount, etc.)

   KCP will discover these schemas in [Step 1](../STEP-1-DISCOVER/README.md) and migrate them in [Step 3](../STEP-3-MIGRATE-DATA/README.md).

</details>
</br>
<details>
<summary><span style="font-size: 1.17em; font-weight: 700;">Optional: Verify MSK Connect connector (for Connector migration track)</span></summary>

The Terraform deployment automatically created an MSK Connect S3 Sink connector that archives orders to S3.

1. List all MSK Connect connectors to verify the orders connector was created:
   ```bash
   python3 setup_connector.py msk-list
   ```

   You should see a connector named `dev-orders-s3-sink` with state `RUNNING`.

2. Get detailed status of the orders S3 sink connector:
   ```bash
   python3 setup_connector.py msk-status
   ```

   This will show you:
   - Connector state and configuration
   - Kafka cluster bootstrap servers
   - S3 bucket destination
   - Autoscaling capacity settings

3. The connector is configured to:
   - Read from the `orders` topic
   - Write messages to an S3 bucket in JSON format
   - Partition data by time (hourly partitions: year/month/day/hour)

4. After running the producer for a few minutes, verify data is being written to S3:
   ```bash
   python3 setup_connector.py check-s3
   ```

   You should see JSON files appearing in the S3 bucket organized by date/time partitions.

   KCP will discover this connector in [Step 1](../STEP-1-DISCOVER/README.md) and migrate it in [Step 3](../STEP-3-MIGRATE-DATA/README.md).

</details>

### Next Steps

Once you've deployed the Gateway, tested the producer and consumer through the Gateway, completed any optional setup tracks you enabled, and generated some data for the source cluster, it's time to begin the migration. In the next step, you will use the KCP CLI to discover and scan your existing Kafka environment.

## Topics

**Next topic:** [Step 1: Discover and Plan](../STEP-1-DISCOVER/README.md)

**Previous topic:** [Workshop Introduction](../README.md)
