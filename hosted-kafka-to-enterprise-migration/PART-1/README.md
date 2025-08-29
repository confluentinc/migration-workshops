
## Part 1 - Set Up the Bastion Host with KCP CLI

How you migrate to Confluent Cloud is dependent on whether your source cluster uses **public** or **private** endpoints. For **public** cluster migrations, you can simply run the KCP CLI directly on your local machine. For **private** clusters, however, you need to temporarily deploy a **bastion host** for the KCP CLI to have access to the cluster. Since **private** clusters are the most common in real-world production scenarios, we will use this approach for the workshop.  

In this section, we will use the KCP CLI to create a **bastion host** that will serve as the migration control plane for moving data from MSK to Confluent Cloud.

### Requirements

Before starting this lab, ensure you have:

1. **AWS CLI configured** with appropriate permissions for MSK, EC2, and VPC services
2. **KCP CLI installed**
3. **Terraform installed** (version 1.0 or later)
4. Completed all prerequisites from the [Workshop Introduction](../README.md).
5. **Deployed the top-level Terraform infrastructure** that creates the MSK cluster and VPC with internet gateway

### Creating the Bastion Host

The bastion host is a critical component that acts as the migration control plane. It will:
- Host the migration tools and scripts
- Provide secure access to both MSK and Confluent Cloud
- Execute the migration commands and monitor progress
- For the workshop only (not production environments), will host our producer and consumer applications

**Note:** The bastion host is configured to use the existing internet gateway that was created by the top-level Terraform infrastructure, ensuring proper internet connectivity without creating duplicate resources. 

#### Using KCP CLI to Create the Bastion Host

1. Navigate to the project directory:
      ```bash
      cd /path/to/hosted-kafka-to-enterprise-migration
      mkdir kcp
      cd kcp
      ```

2. Initialize KCP:
      ```bash
      kcp init
      ```

      This command creates the KCP Readme and a `set_migration_env_vars.sh` script. 

3. Create the bastion host terraform template:
      To do this, you will need the `vpc_id` and `aws_region` values from your Terraform outputs. 
      
      If you need to retrieve these Terraform output values, you can run the following commands: 

      ```bash 
      cd ../terraform/
      terraform output
      ``` 
      Then, make sure to return to the `kcp` directory: 
      ```bash 
      cd ../kcp/
      ``` 

      Now, you can create the bastion host Terraform using the KCP CLI. Make sure to substitute your own values for <YOUR_AWS_REGION> and <YOUR_VPC_ID>: 
      ```bash 
      kcp create-asset bastion-host \
      --region <YOUR_AWS_REGION> \
      --bastion-host-cidr 10.0.100.0/24 \
      --vpc-id <YOUR_VPC_ID>
      ``` 

4. **Deploy the bastion host**:
      ```bash
      cd bastion_host
      terraform init 
      terraform apply --auto-approve
      ```

5. **Update the bastion host security group to allow SSH access from your local machine**:

      By default, the KCP-created bastion host only allows connections from EC2 Instance Connect IP addresses. For the purposes of the workshop, you will need to to access the instance from your local machine. We will update the bastion host security group to allow connections from your public IP address. 
      
      First, get your public IP address:
      ```bash
      curl -s https://checkip.amazonaws.com/
      ```
      
      Then, find the security group ID for the bastion host:
      
      ```bash
      aws ec2 describe-security-groups \
        --filters "Name=tag:Name,Values=migration-bastion-host-security-group*" \
        --query 'SecurityGroups[0].GroupId' \
        --output text \
        --region <YOUR_AWS_REGION>
      ```
      
      Replace `<YOUR_PUBLIC_IP>` with your actual public IP address and `<SECURITY_GROUP_ID>` with the security group ID you found, then run the following command to allow connections:
      ```bash
      aws ec2 authorize-security-group-ingress \
        --group-id <SECURITY_GROUP_ID> \
        --protocol tcp \
        --port 22 \
        --cidr <YOUR_PUBLIC_IP>/32 \
        --region <YOUR_AWS_REGION>
      ```

6. Copy the client files onto your bastion host server: 
      ```bash
      scp -i .ssh/migration_rsa -r ../../clients/ ec2-user@<YOUR_BASTION_HOST_PUBLIC_IP>:~/
      ```

7. SSH into your bastion host: 
      ```bash
      ssh -i .ssh/migration_rsa ec2-user@<YOUR_BASTION_HOST_PUBLIC_IP>
      ```

#### Next Steps

Now, you've created the bastion host, transferred the necessary client files, and gained remote access to the bastion host via SSH. In the next section, you will explore the resources on our bastion host and test the producer and consumer applications. 

## Topics

**Next topic:** [Part 2: Set Up and Test Client Applications](../PART-2/README.md)

**Previous topic:** [Workshop Introduction](../README.md)
