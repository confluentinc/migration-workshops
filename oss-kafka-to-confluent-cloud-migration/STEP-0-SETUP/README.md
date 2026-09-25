## Step 0 - Setup

Before beginning the migration, you'll deploy the source environment in AWS — an open-source
Apache Kafka broker on EC2 and a bastion host — then deploy the migration Gateway and verify
your client applications run through it.

## Prerequisites

- **AWS account** with permissions for VPC, EC2, Elastic Load Balancing, Route 53, S3, IAM (one
  instance role) and VPC endpoints / endpoint services, and **AWS credentials** you can export
  in a shell (on your laptop, and later on the bastion for the KCP-generated Terraform).
- **Confluent Cloud account** and a **Cloud resource management API key**
  ([sign up](https://confluent.cloud/signup), then create the key under **API keys**).
- **On your laptop:** [Terraform](https://developer.hashicorp.com/terraform/install) 1.5+ and
  git. Everything else (KCP, Helm, k3s, Vault, Java, Kafka tools) is installed on the bastion
  for you.

  ```bash
  brew tap hashicorp/tap
  brew install hashicorp/tap/terraform git
  ```

> **Cost & cleanup:** everything here **bills hourly** — the Enterprise cluster, the Confluent
> PrivateLink gateways, the AWS NAT gateway, NLB, VPC endpoint and EC2 instances. KCP's
> generated environment also enables the Stream Governance **Advanced** package. Run
> [Step 5: Cleanup](./STEP-5-CLEANUP/README.md) as soon as you finish.

### Deploy the source environment (on your laptop)

1. Clone the repo and change into the workshop's Terraform directory:
   ```bash
   git clone https://github.com/confluentinc/migration-workshops/
   cd migration-workshops/oss-kafka-to-confluent-cloud-migration/terraform
   ```

2. Export your AWS credentials:
   ```bash
   export AWS_ACCESS_KEY_ID="<YOUR_AWS_ACCESS_KEY_ID>"
   export AWS_SECRET_ACCESS_KEY="<YOUR_AWS_SECRET_ACCESS_KEY>"
   export AWS_SESSION_TOKEN="<YOUR_AWS_SESSION_TOKEN>"
   ```

3. Deploy (about 5 minutes):
   ```bash
   terraform init
   terraform apply
   ```
   This creates a VPC with a public and a private subnet, a NAT gateway (outbound only), the
   Kafka broker in the private subnet, the bastion in the public subnet, the private DNS zone
   `oss-workshop.internal`, and a workshop CA that signs the broker's certificate.

   > The defaults deploy to `us-west-2`. Override with `-var aws_region=<region>`. To SSH from
   > your laptop (needed only for the optional KCP UI tunnel in Step 1), also pass
   > `-var 'allowed_ssh_cidrs=["<your-ip>/32"]'`. The bastion accepts SSH only from EC2
   > Instance Connect and the CIDRs you list; the broker accepts connections only from inside
   > the VPC.

4. Note the outputs — `bastion_instance_id` and `kafka_bootstrap` in particular:
   ```bash
   terraform output
   ```

### Connect to the bastion

The bastion is your migration control plane for the rest of the workshop: it runs the Gateway,
KCP, and the producer/consumer, all inside the VPC.

1. Open the [EC2 Console](https://console.aws.amazon.com/ec2/home#Instances:instanceState=running)
   in your region and select the `oss-migration-bastion` instance.
2. Choose **Connect** → **EC2 Instance Connect** → **Connect**. A terminal opens in your browser.
   (Or, if you set `allowed_ssh_cidrs`, run the `ssh_command` from `terraform output`.)
3. Wait for the bastion's first-boot setup to finish (it installs k3s, KCP and the other tools,
   then unpacks the workshop scripts that `terraform apply` uploaded — a few minutes):
   ```bash
   cloud-init status --wait
   ```
   It should print `status: done`. If it prints `status: error`, the last lines of
   `sudo tail -n 30 /var/log/cloud-init-output.log` show the step that failed. Then open a fresh
   shell so `~/.bashrc` loads the environment the setup wrote:
   ```bash
   exec bash -l
   cd ~/oss-workshop
   cat workshop.env
   ```
   `workshop.env` holds the values later steps use — the broker's bootstrap, private IP and
   subnet, the VPC ID, and the CIDRs reserved for PrivateLink. Every new shell sources it.

### Set up the client applications

1. Install the Python client dependencies into a virtualenv:
   ```bash
   cd ~/oss-workshop/clients
   ./setup.sh
   source .venv/bin/activate
   ```
   **Activate the venv in every client tab** before running any `python3` client.

2. Confirm the bastion can reach the source broker. This connects over SASL_SSL, verifies the
   broker's certificate against the workshop CA, and lists the topics:
   ```bash
   source env.oss
   python3 kafka_config.py --check
   ```
   You should see `connected; topics = ['orders']`. If the connection times out, the broker may
   still be booting — its setup runs in the background; retry after a minute.

### Deploy the migration Gateway

You'll use the **Confluent Cloud Gateway** for a **zero-cut migration** — your clients connect
through the Gateway from the start, and during the cutover in Step 4 traffic is redirected to
Confluent Cloud without stopping or reconfiguring any client.

The Gateway runs on k3s on the bastion, deployed via Confluent for Kubernetes (CFK). In this
step it runs in **passthrough mode**: client SCRAM-SHA-512 credentials flow straight through to
the source broker, over SASL_SSL.

1. Deploy it (this installs CFK, creates a truststore from the workshop CA, and applies the
   Gateway):
   ```bash
   cd ~/oss-workshop/gateway
   ./setup_gateway.sh
   ```

2. Verify the Gateway is running:
   ```bash
   kubectl get pods -n confluent
   kubectl get gateways.platform.confluent.io -n confluent
   ```

   > **Note:** use the fully-qualified `gateways.platform.confluent.io`. The bare
   > `kubectl get gateway` resolves to the Kubernetes Gateway API CRD that k3s/Traefik
   > registers, which is empty.

### Test the producer and consumer through the Gateway

1. In your current tab, start the producer through the Gateway:
   ```bash
   cd ~/oss-workshop/clients
   source .venv/bin/activate
   source env.gateway
   python3 orders_producer.py
   ```
   **Leave it running.** It connects to `localhost:9595` (the Gateway), which routes to the
   source broker.

2. Open a second EC2 Instance Connect tab to the bastion and start the consumer:
   ```bash
   cd ~/oss-workshop/clients
   source .venv/bin/activate
   source env.gateway
   python3 orders_consumer.py
   ```
   **Leave it running.** You should see orders flowing.

### Next Steps

Your source environment is live and your clients are running through the Gateway. Next you'll
use the KCP CLI to discover the source cluster and build the migration inventory. Open a
**third** bastion tab for the KCP commands.

## Topics

**Next topic:** [Step 1: Discover and Plan](../STEP-1-DISCOVER/README.md)

**Previous topic:** [Workshop Introduction](../README.md)
