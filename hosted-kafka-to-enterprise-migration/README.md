#  Migrating from Hosted Kafka services to Confluent Cloud Enterprise Clusters

Migrating from Hosted Kafka services to Confluent Cloud provides a number of benefits, including:

- **Fully-managed, elastic, and resilient infrastructure** - Spend less time managing infrastructure and more time creating business value. 
- **Reduced total cost of ownership** - Operate more efficiently, with lower infrastructure cost, DevOps overhead, and downtime risk. 
- **Rich connector ecosystem** - Easily build an enterprise-wide data fabric with over 200 connectors to the applications and systems you use. 
- **Strong security and governance controls** - Enhance security and governance of your data with enterprise-grade features, including Stream Governance, Client-side Field Level Encryption (CSFLE), role-based access control (RBAC), audit logs, and more.
- **Mix of cluster types** - Mix-and-match Confluent Cloud cluster types to address your use cases and strike the perfect balance of cost, latency, and throughput. 


This repository steps through an example migration from hosted Kafka services to Confluent Cloud Enterprise Clusters. This workshop uses Cluster Linking to create matching mirror topics, sync all new and historical data, and match your consumer offsets, meaning you no longer have to recreate topics by hand or deal with missing or duplicate messages when you migrate producers and consumers. In addition, it uses the Confluent KCP CLI to simplify infrastructure provisioning for migration resources.

In this workshop, we will use Terraform to deploy the source MSK cluster infrastructure and the Confluent KCP CLI to deploy all migration infrastructure.

## Prerequisites 

To perform this workshop yourself, you will need the following: 

* An active AWS Account with read and write permissions for Amazon MSK, Amazon EC2, and AWS VPC resources. 
* An active Confluent Cloud account and API key with cloud management permissions. 
* **Command Line tools**: Run ```brew install awscli make terraform```

  * **Terraform (v1.9.5+)** - The demo resources are automatically created using [Terraform](https://www.terraform.io). In addition to having Terraform installed locally, you will need to provide your cloud provider credentials so Terraform can create and manage the resources for you.
  * **AWS CLI** - Terraform uses the AWS CLI to manage AWS resources
  * **Go (v1.24+)** - Install using this [link](https://go.dev/doc/install)
  * **Make** - Required to utilize the KCP CLI 
    
* **Unix machine** - The Terraform script requires a Unix environment. If you're using a Windows machine, consider deploying an EC2 instance with CentOS and run the deployment steps from there.

## Setup

### Provision source resources

First, we need to create a sample hosted Kafka environment - in this case, an Amazon MSK cluster - that we will migrate away from in the workshop. 

1. Clone the repo onto your local development machine using `git clone <repo>`.
2. Change directory to demo repository and terraform directory.

    ```bash
    cd hosted-kafka-to-enterprise-migration/terraform
    ```
3. Set the environment variables for your AWS role. Make sure to enter your own values for `<YOUR_AWS_ACCESS_KEY_ID>`, `<YOUR_AWS_SECRET_ACCESS_KEY>`, and `<YOUR_AWS_SESSION_TOKEN>`. 
    ```bash
    export AWS_ACCESS_KEY_ID="<YOUR_AWS_ACCESS_KEY_ID>"
    export AWS_SECRET_ACCESS_KEY="<YOUR_AWS_SECRET_ACCESS_KEY>"
    export AWS_SESSION_TOKEN="<YOUR_AWS_SESSION_TOKEN>"
    ```
   
5. Deploy the starting workshop resources.

    ```bash
    terraform init
    terraform apply --auto-approve
    ```

The terraform script will take 25-30 minutes to deploy. When the script completes, be sure to save the Terraform output values to a note. We will use these values in later workshop sections. 

**You can open a new terminal window and complete the following setup steps while you wait.**

### Installing the KCP CLI

Next, we need to install the [Confluent KCP CLI](https://github.com/confluentinc/kcp), a command line tool that streamlines hosted Kafka migrations by completing the necessary environment scans and infrastructure configuration. As we will see, the KCP CLI takes care of much of the heavy lifting of the migration for us. Feel free to [explore the KCP CLI in more detail here](https://github.com/confluentinc/kcp).

#### Build/Install from Source

> [!TIP] 
> Make sure you have Go 1.24+ installed before building from source

1. Clone the repository

    ```bash
    git clone https://github.com/confluentinc/kcp.git
    cd kcp
    ```

2. Install to system path. This action requires sudo permissions. 
  
    ```bash
    make install
    ```

    This may take 1-2 minutes. 

## Workshop
> Estimated time: 45 minutes

In this workshop, you will complete the following parts: 

- [Part 1: Set Up the Bastion Host with KCP CLI](./PART-1/README.md)
- [Part 2: Set Up and Test Client Applications](./PART-2/README.md)
- [Part 3: Provision Migration Resources with KCP CLI](./PART-3/README.md) 
- [Part 4: Cutover Client Applications to Confluent Cloud](./PART-4/README.md)
- [Part 5: Cleanup Resources](./PART-5/README.md)

## Topics

**Next topic:** [Part 1: Set Up the Bastion Host with KCP CLI](./PART-1/README.md)

## Clean-up
Once you are finished with this workshop, remember to destroy the resources you created to avoid incurring in charges. You can always spin it up again anytime you want.