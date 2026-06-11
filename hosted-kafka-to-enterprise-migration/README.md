# Migrating from Hosted Kafka services to Confluent Cloud Enterprise Clusters

Migrating from Hosted Kafka services to Confluent Cloud provides a number of benefits, including:

- **Fully-managed, elastic, and resilient infrastructure** - Spend less time managing infrastructure and more time creating business value.
- **Reduced total cost of ownership** - Operate more efficiently, with lower infrastructure cost, DevOps overhead, and downtime risk.
- **Rich connector ecosystem** - Easily build an enterprise-wide data fabric with over 80 fully-managed connectors to the applications and systems you use.
- **Strong security and governance controls** - Enhance security and governance of your data with enterprise-grade features, including Stream Governance, Client-side Field Level Encryption (CSFLE), role-based access control (RBAC), audit logs, and more.
- **Mix of cluster types** - Mix-and-match Confluent Cloud cluster types to address your use cases and strike the perfect balance of cost, latency, and throughput.

This repository steps through an example migration from hosted Kafka services to Confluent Cloud Enterprise Clusters. This workshop follows a proven **four-step migration framework** — **Discover and Plan, Provision Infrastructure, Migrate Data, and Migrate Clients** — using the Confluent KCP CLI, KCP UI, and **Confluent Cloud Gateway** to automate each phase. 

**Kafka Copy Paste (KCP)** is a tool from Confluent that orchestrates the entire migration process, from discovery and planning to actual client cutovers, with just a few CLI commands. For more details on all of the migration support that KCP provides, be sure to check out the [KCP documentation](https://confluentinc.github.io/kcp).  

KCP uses **Cluster Linking** under the hood to facilitate the data migration process. Cluster Linking creates matching mirror topics, syncs all new and historical data, and matches your consumer offsets, meaning you no longer have to recreate topics by hand or deal with missing or duplicate messages when you migrate producers and consumers.

In this workshop, we will use Terraform to deploy the source MSK cluster infrastructure and the Confluent KCP CLI to deploy all migration infrastructure. Gateway runs on a lightweight Kubernetes (k3s) instance on the bastion host.

## Prerequisites

To perform this workshop yourself, you will need the following:

- An active AWS Account with read and write permissions for Amazon MSK, Amazon EC2, and AWS VPC resources.
- An active Confluent Cloud account and API key with cloud management permissions.
- **Command Line tools:**
  - **Terraform (v1.9.5+)** - The demo resources are automatically created using [Terraform](https://www.terraform.io). In addition to having Terraform installed locally, you will need to provide your cloud provider credentials so Terraform can create and manage the resources for you.
  - **AWS CLI** - Terraform uses the AWS CLI to manage AWS resources
  For Mac:
  ```bash
  brew install awscli git terraform
  ```
  For Windows:
  ```cmd
  winget install --id Amazon.AWSCLI -e && `
  winget install --id HashiCorp.Terraform -e
  ```

## Setup

### Provision source resources

First, we need to create a sample hosted Kafka environment - in this case, an Amazon MSK cluster - that we will migrate away from in the workshop.

1. Clone the repo onto your local machine.
  ```bash
    git clone https://github.com/confluentinc/migration-workshops/
  ```
2. Change directory to demo repository and terraform directory.
  ```bash
    cd migration-workshops/hosted-kafka-to-enterprise-migration/terraform
  ```
3. Set the environment variables for your AWS role. Make sure to enter your own values for `<YOUR_AWS_ACCESS_KEY_ID>`, `<YOUR_AWS_SECRET_ACCESS_KEY>`, and `<YOUR_AWS_SESSION_TOKEN>`.
  For Unix systems:
    For Windows systems:
4. Deploy the starting workshop resources.
  For an interactive selector that lets you opt in to the ACL, Schema, and Connector migration tracks:

The Terraform script will take approximately 30-40 minutes to deploy. When the script completes, be sure to save the Terraform output values to a note. We will use these values in later workshop sections.

**You can move on to the following steps while the resources are deploying.**

### Create Confluent Cloud Account and API Key

1. Head over to the [Confluent Cloud signup page](https://confluent.cloud/signup) and sign up for a new account.
2. Watch your inbox for a confirmation email. Once you get the email, follow the link to proceed.
3. At this point, you will be asked to create a cluster. **You can skip this step, as we will set up all required resources in the workshop.**
4. Go to the [API keys page](https://confluent.cloud/settings/api-keys). You can also navigate to the API keys page by expanding the sidebar menu in the Confluent Cloud Console and selecting API keys.
5. Click **Add API key**.
6. Select **My account** for the API key. Then, select **Next**.
7. Select **Cloud resource management** as the resource scope for the API key. Then, select **Next**.
8. Give the API Key a name, then select **Next**.
9. Click **Create API key**. Then, **make sure you download the API key on this page. If you forget, you'll need to create a new key to download the values.**

## Workshop

> Estimated time: 90 minutes

This workshop demonstrates a comprehensive migration following the four-step framework:

- **Discover and Plan**: Scan your source environment to build a complete inventory of topics, ACLs, schemas, and clients
- **Provision Infrastructure**: Generate and apply Terraform to create target and migration infrastructure automatically
- **Migrate Data**: Replicate topics via Cluster Linking, migrate ACLs and schemas using KCP, and recreate connectors as fully-managed connectors in Confluent Cloud
- **Migrate Clients**: Execute a zero-cut migration via Gateway, seamlessly redirecting all client traffic to Confluent Cloud

> **Optional migration tracks:** ACL, Schema Registry, and Connector migrations are optional and **disabled by default** to keep the workshop footprint small. Run `terraform/deploy.sh` for an interactive selector, or set `enable_acl_migration`, `enable_schema_migration`, `enable_connector_migration` in `terraform/terraform.tfvars`. The core topic-migration flow runs regardless.

In this workshop, you will complete the following steps:

- [Step 0: Setup](./STEP-0-SETUP/README.md) — Access bastion host, deploy Gateway, test client applications through Gateway
- [Step 1: Discover and Plan](./STEP-1-DISCOVER/README.md) — Scan your MSK environment with KCP CLI
- [Step 2: Provision Infrastructure](./STEP-2-PROVISION/README.md) — Deploy target and migration infrastructure, configure Gateway target
- [Step 3: Migrate Data](./STEP-3-MIGRATE-DATA/README.md) — Migrate topics (and any optional tracks you enabled: ACLs, schemas, connectors)
- [Step 4: Migrate Clients](./STEP-4-MIGRATE-CLIENTS/README.md) — Execute zero-cut migration via Gateway
- [Step 5: Cleanup Resources](./STEP-5-CLEANUP/README.md) — Tear down workshop resources

## Topics

**Next topic:** [Step 0: Setup](./STEP-0-SETUP/README.md)

## Clean-up

Once you are finished with this workshop, remember to destroy the resources you created to avoid incurring charges. You can always spin it up again anytime you want.