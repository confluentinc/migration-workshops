## Part 2 - Set Up and Test Client Applications

By now, you've set up the bastion host server required to manage the private MSK cluster migration to Confluent Cloud. In this section, we will set up and test the MSK client producer and consumer applications to ensure they're working correctly with the source MSK cluster before migration.

### General Requirements

Complete [Part 1: Access the Bastion Host](../PART-1/README.md) before starting Part 2. 

### Explore and Test the Client Applications

#### Configure Environment Variables
1. Move the workshop client resources to your root folder. This will make the workshop easier to navigate in future steps. 

   ```bash
   mkdir clients
   cp -r migration-workshops/hosted-kafka-to-enterprise-migration/clients ~/
   ```

2. Update the `env.msk` file with your MSK cluster configuration:
   ```bash
   cd ~/clients
   # Edit the env.msk file with your actual MSK cluster details
   nano env.msk
   # OR 
   vim env.msk
   ```
3. Ensure the following variables are set correctly. Note, you may need to retrieve these values from the setup Terraform output from the [Workshop Introduction](../README.md):
   - `MSK_BOOTSTRAP_SERVERS`: Your MSK cluster bootstrap servers
   - `MSK_SASL_USERNAME`: Your MSK SASL username
   - `MSK_SASL_PASSWORD`: Your MSK SASL password
4. Source the environment file:
   ```bash
   source env.msk
   ```

#### Run Set Up and Verify Configuration
1. Run the setup script and test the configuration:
   ```bash
   ./setup.sh
   python3 kafka_config.py
   ```

### Test the Producer Application

1. Execute the orders producer application to send test messages:
   ```bash
   python3 orders_producer.py
   ```
2. Verify that messages are being sent successfully to the MSK cluster.

### Test the Consumer Application
1. In a separate terminal session, SSH into the EC2 instance following the steps above. Then, execute the orders consumer application:
   ```bash
   python3 orders_consumer.py
   ```
2. Verify that messages are being consumed correctly from the MSK cluster.

### Stop the producer and consumer 
1. In both terminals, `Ctrl+C` to stop the producer and consumer applications. 


#### Next Steps

Once you've explored the producer and consumer applications and generated some data for the source cluster, it's time to continue with the migration. In the next section, you will create the rest of the migration resources with the KCP CLI. 

**Next topic:** [Part 3: Provision Migration Resources with KCP CLI](../PART-3/README.md)

**Previous topic:** [Part 1: Set Up the Bastion Host with KCP CLI](../PART-1/README.md)
