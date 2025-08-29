## Part 4 - Cutover Client Applications to Confluent Cloud

In this section, you will perform the actual cutover of client applications from MSK to the new Confluent Cloud Enterprise cluster, ensuring zero data loss and minimal downtime. Since you are using your **bastion host** to simulate client actions, you will need to do a bit of preparation by setting up a reverse proxy and configuring DNS entries. 

Mirror topics in Cluster Links can't be written to. To convert a mirror topic to a writable topic, you need to **promote** the topic, which detaches it from the Cluster Link. In this section, you will verify that there's no lag on your mirror topic, and then will promote it to be writable for use with your client applications. Then, you'll be able to perform the cutover with your client apps. 

### Requirements

Complete [Part 3: Provisioning Migration Resources with KCP CLI](../PART-3/README.md) before starting Part 4. 

### Deploy Reverse Proxy and Configure DNS

Before connecting to the Confluent Cloud resources, you need to deploy the reverse proxy and configure DNS entries to enable secure access to your private Confluent Cloud cluster.

#### Step 1: Deploy the Reverse Proxy

Using the KCP CLI, create the `reverse_proxy` terraform resources:
```bash
kcp create-asset reverse-proxy \
--region <YOUR_AWS_REGION> \
--vpc-id <YOUR_VPC_ID> \
--migration-infra-folder migration_infra \
--reverse-proxy-cidr 10.0.45.0/24
```

Navigate to the generated `reverse_proxy` directory and deploy the infrastructure:

```bash
cd reverse_proxy
terraform init
terraform plan
terraform apply
```

When prompted, type `yes` to confirm the deployment.

#### Step 2: Configure Local DNS

The reverse proxy generates a `dns_entries.txt` file containing DNS entries that you must manually add to your local machine's `/etc/hosts` file:

```bash
cat dns_entries.txt
```

Copy the full output, then open the `/etc/hosts` file and append the `dns_entries.txt` contents. 

```bash
nano /etc/hosts
# OR 
vim /etc/hosts
```

### Configure Environment Files
#### Promote the Target Topic
Before running the consumer and producer on the new cluster, you need to promote the mirror topic to make it writable:

1. Login to Confluent Cloud CLI:
   ```bash
   confluent login --no-browser
   ```

2. Set the target environment:
   ```bash
   confluent environment use <target environment>
   ```

3. Set the target cluster:
   ```bash
   confluent kafka cluster use <target cluster>
   ```

4. Promote the mirror topic to make it writable:
   ```bash
   confluent kafka mirror promote orders --link cp-to-cc-link
   ```

   This command will check the replication lag, synchronize everything, and make the topic writable only if it's fully caught up.

### Make the Target Cluster Writable

The mirror topics are read-only by default. To make a mirror topic writable (i.e., change it from read-only, mirrored state to a regular, independent, writable topic) in Confluent Kafka (whether in Confluent Platform or Confluent Cloud with Cluster Linking), you need to use either the promote or failover command. This operation is commonly called "promoting" the mirror topic, and is an essential step in cutover, DR, or migration workflows.

⚠️ **Note:** Mirror topics are read-only topics created and owned by a cluster link. You cannot directly write to these topics; only the cluster link can synchronize data from the source topic. To make the topic writable, you must "convert" it to a regular topic by stopping (detaching) it from the cluster link. This is done by either promoting or failing over the topic. Once promoted or failed over, the mirror topic will permanently stop syncing from its source, and you can produce records to it like any other topic. This operation cannot be reversed—you would need to recreate the topic as a mirror topic if you want to re-establish mirroring.

Execute the following steps to make the mirror topic writable:

1. **Confirm the current status of the mirror topic** (and check that mirroring lag is zero if doing a planned migration):
   ```bash
   confluent kafka mirror describe orders --link cp-to-cc-link
   ```

2. **To promote, ensure network reachability between the destination and source clusters, and that lag is zero.**

3. **Promote the mirror topic**:
   ```bash
   confluent kafka mirror promote orders --link cp-to-cc-link --cluster <ENTERPRISE_CLUSTER_ID>
   ```
   This will check lag, synchronize everything, and make the topic writable only if fully caught up.

### Execute the Cutover

1. If any are running, stop the MSK applications:
   ```bash
   pkill -f "orders_producer.py"
   pkill -f "orders_consumer.py"
   ```

2. Switch to Confluent Cloud environment:
   ```bash
   source env.cc
   ```

3. Start applications against Confluent Cloud:
   ```bash
   python3 orders_producer.py
   ```

   and 

   ```bash
   python3 orders_consumer.py
   ```

You should now see that the `orders_producer.py` and `orders_consumer.py` are working with your new Confluent Cloud Enterprise Cluster. You should see in the `orders_consumer.py` output that the previous consumer offsets were conserved during the migration, eliminating any data loss or duplicated data. 

### Next Steps

You have successfully cutover your applications from MSK to Confluent Cloud. Your applications are now running on the new platform with all historical data preserved. Feel free to take some time to explore your new Confluent Cloud Enterprise Cluster. In the next section, we will safely clean up the workshop resources.

## Topics

**Next topic:** [Part 5: Cleanup Resources](../PART-5/README.md)

**Previous topic:** [Part 3: Provisioning Migration Resources with KCP CLI](../PART-3/README.md)
