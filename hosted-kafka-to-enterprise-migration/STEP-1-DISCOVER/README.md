## Step 1 - Discover and Plan

Before migrating any infrastructure, you need to understand what you have. In this step, you'll use the KCP CLI to automatically discover and catalog the resources present in your source Kafka environment — topics and clients always, plus any ACLs, schemas, and connectors that exist (these depend on which optional tracks you enabled at deploy time). The result is a `kcp-state.json` file that serves as the **single source of truth** for your migration, driving all subsequent steps.

### Requirements

Complete [Step 0: Setup](../STEP-0-SETUP/README.md) before starting Step 1.

### Scan Your AWS Resources

1. Navigate to your home directory on your bastion host:
  ```bash
   cd ~/
  ```
2. Set the environment variables for your AWS role. Make sure to enter your own values for `<YOUR_AWS_ACCESS_KEY_ID>`, `<YOUR_AWS_SECRET_ACCESS_KEY>`, and `<YOUR_AWS_SESSION_TOKEN>`.
  ```bash
    export AWS_ACCESS_KEY_ID="<YOUR_AWS_ACCESS_KEY_ID>"
    export AWS_SECRET_ACCESS_KEY="<YOUR_AWS_SECRET_ACCESS_KEY>"
    export AWS_SESSION_TOKEN="<YOUR_AWS_SESSION_TOKEN>"
  ```
3. Use the KCP CLI to scan your AWS region for Kafka resources and generate a report. If you changed the default region, use the region where all of your workshop resources are deployed, for example, `us-west-2`:
  ```bash
   kcp discover --region us-west-2
  ```
  > **Tip:** You can use `--skip-topics`, `--skip-costs`, or `--skip-metrics` flags to speed up discovery if you don't need those details.
   This command generates two files (`kcp-state.json` and `msk-credentials.yaml`) that contain information about your MSK resources in your chosen AWS region. You should see a cluster called `msk-migration-cluster` in the output.
   Export the Cluster ARN for use in subsequent steps:
4. Add your cluster credentials to the `msk-credentials.yaml` file.
  ```bash
   nano msk-credentials.yaml
  ```
   Enter the MSK cluster SASL username ("msk-user") and password ("ChangeMe123!") into the appropriate fields in the `msk-credentials.yaml` file and save it.
5. Use the KCP CLI to perform a cluster-level scan on your source cluster:
  ```bash
   kcp scan clusters \
   --source-type msk \
   --state-file kcp-state.json \
   --credentials-file msk-credentials.yaml
  ```
   This deep scan discovers topics, consumer groups, and any ACLs, schemas, or connectors present on your MSK cluster. The results are stored in `kcp-state.json`, which will drive the provisioning and migration steps that follow.

<details>
<summary><b>Optional: Visualize with the KCP UI</b></summary>

KCP includes a local web UI that lets you upload your `kcp-state.json` file to visualize migration costs, metrics, and cluster details. The UI runs on the bastion host and you access it through an SSH tunnel.

1. **Start the KCP UI on the bastion host:**
  ```bash
   kcp ui
  ```
   The UI listens on port 5556 by default.
2. **Export the connection details as environment variables** from a terminal on your laptop (in the `terraform` directory):
  ```bash
   export BASTION_IP=$(terraform output -raw bastion_host_public_ip)
   export SSH_KEY_PATH=$(terraform output -raw bastion_ssh_key_path)
  ```
3. **Download `kcp-state.json`** from the bastion to your laptop (same terminal, so the variables are set):
  ```bash
   scp -i "$SSH_KEY_PATH" ec2-user@"$BASTION_IP":~/kcp-state.json .
  ```
4. **Open an SSH tunnel** (same terminal):
  ```bash
   ssh -i "$SSH_KEY_PATH" -L 5556:localhost:5556 -N ec2-user@"$BASTION_IP"
  ```
  > **Note:** The `-N` flag means SSH will not open a shell — the command will appear to hang with no output. This is normal. The tunnel is active as long as the command is running. Press `Ctrl+C` to close it when done.
  >
  > If the command hangs for more than 10 seconds without connecting, verify your IP is allowed by the bastion security group, or use the EC2 Instance Connect browser method from [Step 0](../STEP-0-SETUP/README.md) instead.
5. **Open the KCP UI** in your browser at [http://localhost:5556](http://localhost:5556).
6. **Upload the state file** through the KCP UI in your browser and explore costs, metrics, and cluster details.

</details>



### Next Steps

You now have a complete inventory of your source Kafka environment captured in `kcp-state.json`. In the next step, you'll use this state file to provision all target and migration infrastructure on Confluent Cloud.

## Topics

**Next topic:** [Step 2: Provision Infrastructure](../STEP-2-PROVISION/README.md)

**Previous topic:** [Step 0: Setup](../STEP-0-SETUP/README.md)