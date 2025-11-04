
## Part 1 - Access the Bastion Host

How you migrate to Confluent Cloud is dependent on whether your source cluster uses **public** or **private** endpoints. For **public** cluster migrations, you can simply run the KCP CLI directly on your local machine. For **private** clusters, however, you need to temporarily deploy a **bastion host** for the KCP CLI to have access to the cluster. Since **private** clusters are the most common in real-world production scenarios, we will use this approach for the workshop.  

In this section, we will access the **bastion host** created during setup. The bastion host will serve as the migration control plane for moving data from MSK to Confluent Cloud.

### Requirements

Before starting this lab, ensure you have:

1. Completed all prerequisites from the [Workshop Introduction](../README.md).
2. **Deployed the top-level Terraform infrastructure** that creates the MSK cluster and VPC with internet gateway

### Creating the Bastion Host

The bastion host is a critical component that acts as the migration control plane. It will:
- Host the migration tools and scripts
- Provide secure access to both MSK and Confluent Cloud
- Execute the migration commands and monitor progress
- For the workshop only (not production environments), will host our producer and consumer applications

### Instructions

1. Navigate to the [AWS EC2 Console](https://us-west-2.console.aws.amazon.com/ec2/home?region=us-west-2#Instances:instanceState=running) and click the instance ID for the `dev-migration-bastion-host` instance. 

2. Select the **Connect** button. 

3. Leave all default selections, and choose **Connect**. This opens a connection to your EC2 instance in the browser. 

#### Next Steps

Now, you've accessed the bastion host. In the next section, you will explore the resources on our bastion host and test the producer and consumer applications. 

## Topics

**Next topic:** [Part 2: Set Up and Test Client Applications](../PART-2/README.md)

**Previous topic:** [Workshop Introduction](../README.md)
