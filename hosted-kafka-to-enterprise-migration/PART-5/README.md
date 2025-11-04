## Part 5 - Cleanup Resources

In this final section, we will safely shut down all workshop resources and clean up the migration environment. 

### Cleanup Migration Resources
1. Navigate to the `migration_infra` folder on your bastion host and destroy the Terraform resources. 

   ```bash
   cd ~/migration_infra
   terraform destroy
   ```

   You'll need to enter your Confluent Cloud API Key and API Secret from the [Workshop Introduction](../README.md). Note, this is **not** the Cluster API Key created with the `migration_infra` resources. You'll also need to re-enter the SASL username and password for the MSK cluster. 

2. Navigate to the `reverse_proxy` folder on your bastion host and destroy the Terraform resources. 

   ```bash
   cd ~/reverse_proxy
   terraform destroy
   ```

### Cleanup MSK Infrastructure
1. Navigate to the `terraform` directory and destroy the Terraform resources:
   ```bash
   cd path/to/hosted-kafka-to-enterprise-migration/terraform
   terraform destroy
   ```

### Check for remaining Confluent Cloud Resources
1. Navigate to the [Confluent Cloud Console](http://confluent.cloud) and sign in.

2. Select **Environments**, and if present, select the environment you created for the workshop. 

3. Select **Clusters**, and if present, select the cluster you created in the workshop. 

4. Navigate to **Cluster Settings** and select **Delete cluster**. 

5. Navigate back to your workshop environment, select the **More** dropdown, then select **Delete**. 

6. Open the **right-side menu** in Confluent Cloud and select **API Keys**. 

7. Select any **API Keys** related to the workshop environment, and then select the **Delete API key** button. 

### Verify AWS Resource Deletion
1. In your AWS account, verify that the `dev-msk-vpc` was deleted. 

2. In **Amazon S3**, confirm that your Amazon S3 Bucket beginning with `dev-msk-logs-` was deleted. You may have to empty the bucket in order to delete it. 

### Workshop Completion

Congratulations! You have successfully completed the Hosted Kafka to Confluent Cloud Enterprise Migration Workshop. You have:

- Successfully migrated your applications from MSK to Confluent Cloud
- Preserved all historical data during the migration
- Established a robust production-ready environment on Confluent Cloud
- Learned best practices for enterprise Kafka migrations
- Gained hands-on experience with the KCP CLI and migration tools
- Cleaned up all workshop resources

## Topics

**Previous topic:** [Part 4: Cutover Client Applications to Confluent Cloud](../PART-4/README.md)

**Back to:** [Workshop Overview](../README.md)
