# Get availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC Configuration
resource "aws_vpc" "msk_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.environment}-msk-vpc"
  }
}

# Internet Gateway for the VPC
resource "aws_internet_gateway" "msk_igw" {
  count = var.create_internet_gateway ? 1 : 0

  vpc_id = aws_vpc.msk_vpc.id

  tags = {
    Name = "${var.environment}-msk-igw"
  }
}

# Private Subnets for MSK (private networking only)
resource "aws_subnet" "msk_private_subnets" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.msk_vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  availability_zone       = "${var.aws_region}${var.availability_zones[count.index]}"
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.environment}-msk-private-subnet-${var.availability_zones[count.index]}"
    Type = "Private"
  }
}





# Route Table for Private Subnets (no internet access)
resource "aws_route_table" "msk_private_rt" {
  vpc_id = aws_vpc.msk_vpc.id

  tags = {
    Name = "${var.environment}-msk-private-rt"
  }
}





# Route Table Associations for Private Subnets
resource "aws_route_table_association" "msk_private_rta" {
  count          = length(aws_subnet.msk_private_subnets)
  subnet_id      = aws_subnet.msk_private_subnets[count.index].id
  route_table_id = aws_route_table.msk_private_rt.id
}



# Security Group for MSK Cluster (Private Access Only)
resource "aws_security_group" "msk_cluster_sg" {
  name        = "${var.environment}-msk-cluster-sg"
  description = "Security group for MSK cluster with private access"
  vpc_id      = aws_vpc.msk_vpc.id

  # Kafka broker communication - SASL_SSL (SCRAM)
  ingress {
    from_port   = 9096
    to_port     = 9096
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Kafka SASL_SSL (SCRAM)"
  }

  # Kafka broker communication - SASL_SSL (IAM) - required for MSK Connect
  ingress {
    from_port   = 9098
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Kafka SASL_SSL (IAM)"
  }

  # KRaft Controller communication (for internal cluster communication)
  ingress {
    from_port   = 9093
    to_port     = 9093
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "KRaft Controller"
  }

  # JMX monitoring ports
  ingress {
    from_port   = 11001
    to_port     = 11002
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "JMX monitoring"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-msk-cluster-sg"
  }
}

# Security Group for MSK Clients
resource "aws_security_group" "msk_client_sg" {
  name        = "${var.environment}-msk-client-sg"
  description = "Security group for MSK clients"
  vpc_id      = aws_vpc.msk_vpc.id

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-msk-client-sg"
  }
}



# CloudWatch Log Group for MSK
resource "aws_cloudwatch_log_group" "msk_log_group" {
  count             = var.enable_logging ? 1 : 0
  name              = "/aws/msk/${var.cluster_name}"
  retention_in_days = 14

  tags = {
    Name = "${var.environment}-msk-log-group"
  }
}

# S3 Bucket for MSK logs
resource "aws_s3_bucket" "msk_logs_bucket" {
  count         = var.enable_logging ? 1 : 0
  bucket        = "${var.environment}-msk-logs-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = {
    Name = "${var.environment}-msk-logs-bucket"
  }
}

resource "aws_s3_bucket_versioning" "msk_logs_bucket_versioning" {
  count  = var.enable_logging ? 1 : 0
  bucket = aws_s3_bucket.msk_logs_bucket[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "msk_logs_bucket_encryption" {
  count  = var.enable_logging ? 1 : 0
  bucket = aws_s3_bucket.msk_logs_bucket[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 8
}

# MSK Cluster Configuration
resource "aws_msk_configuration" "msk_config" {
  kafka_versions = [var.kafka_version]
  name           = "${var.environment}-msk-configuration"

  server_properties = <<PROPERTIES
auto.create.topics.enable=true
default.replication.factor=3
min.insync.replicas=2
num.partitions=3
num.replica.fetchers=2
replica.lag.time.max.ms=30000
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600
socket.send.buffer.bytes=102400
unclean.leader.election.enable=false
PROPERTIES

  description = "MSK configuration for ${var.environment} environment"
}

# KMS Key for MSK encryption
resource "aws_kms_key" "msk_kms_key" {
  description             = "KMS key for MSK cluster encryption"
  deletion_window_in_days = 7

  tags = {
    Name = "${var.environment}-msk-kms-key"
  }
}

resource "aws_kms_alias" "msk_kms_alias" {
  name          = "alias/${var.environment}-msk-key"
  target_key_id = aws_kms_key.msk_kms_key.key_id
}

# MSK SCRAM Secret for authentication
resource "aws_secretsmanager_secret" "msk_scram_secret" {
  name                    = "AmazonMSK_${var.environment}-msk-scram-secret"
  description             = "SCRAM credentials for MSK cluster"
  kms_key_id              = aws_kms_key.msk_kms_key.key_id
  recovery_window_in_days = 0 # For demo purposes, set to 0 for immediate deletion
}

resource "aws_secretsmanager_secret_version" "msk_scram_secret" {
  secret_id = aws_secretsmanager_secret.msk_scram_secret.id
  secret_string = jsonencode({
    username = var.msk_username
    password = var.msk_password
  })
}

# MSK Cluster (Private with SASL SCRAM only)
resource "aws_msk_cluster" "msk_cluster" {
  cluster_name           = var.cluster_name
  kafka_version          = var.kafka_version
  number_of_broker_nodes = length(var.availability_zones) * var.number_of_broker_nodes

  broker_node_group_info {
    instance_type   = var.broker_node_instance_type
    client_subnets  = aws_subnet.msk_private_subnets[*].id
    security_groups = [aws_security_group.msk_cluster_sg.id]
    
    # Private networking only - no public access
    connectivity_info {
      public_access {
        type = "DISABLED"
      }
    }

    storage_info {
      ebs_storage_info {
        volume_size = var.broker_node_storage_size
      }
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.msk_config.arn
    revision = aws_msk_configuration.msk_config.latest_revision
  }

  encryption_info {
    encryption_at_rest_kms_key_arn = aws_kms_key.msk_kms_key.arn
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  # Authentication configuration - SASL SCRAM and IAM (IAM required for MSK Connect)
  client_authentication {
    unauthenticated = false
    sasl {
      scram = true
      iam   = true
    }
  }

  # Logging configuration
  dynamic "logging_info" {
    for_each = var.enable_logging ? [1] : []
    content {
      broker_logs {
        cloudwatch_logs {
          enabled   = true
          log_group = aws_cloudwatch_log_group.msk_log_group[0].name
        }
        firehose {
          enabled = false
        }
        s3 {
          enabled = true
          bucket  = aws_s3_bucket.msk_logs_bucket[0].id
          prefix  = "msk-logs/"
        }
      }
    }
  }

  open_monitoring {
    prometheus {
      jmx_exporter {
        enabled_in_broker = var.enable_monitoring
      }
      node_exporter {
        enabled_in_broker = var.enable_monitoring
      }
    }
  }

  tags = {
    Name        = var.cluster_name
    Environment = var.environment
  }
}

# ------------------------------------------------------
# Glue Schema Registry
# ------------------------------------------------------

# Glue Schema Registry for MSK schemas
resource "aws_glue_registry" "msk_schemas" {
  count         = var.enable_schema_migration ? 1 : 0
  registry_name = "${var.environment}-msk-schemas"

  tags = {
    Name        = "${var.environment}-msk-schemas"
    Environment = var.environment
  }
}

# Glue Schema: orders-key (Avro)
resource "aws_glue_schema" "orders_key" {
  count             = var.enable_schema_migration ? 1 : 0
  schema_name       = "orders-key"
  registry_arn      = aws_glue_registry.msk_schemas[0].arn
  data_format       = "AVRO"
  compatibility     = "BACKWARD"
  schema_definition = jsonencode({
    type = "int"
  })

  tags = {
    Name = "${var.environment}-orders-key-schema"
  }
}

# Glue Schema: orders-value (Avro)
resource "aws_glue_schema" "orders_value" {
  count             = var.enable_schema_migration ? 1 : 0
  schema_name       = "orders-value"
  registry_arn      = aws_glue_registry.msk_schemas[0].arn
  data_format       = "AVRO"
  compatibility     = "BACKWARD"
  schema_definition = jsonencode({
    type      = "record"
    name      = "Order"
    namespace = "com.example.orders"
    fields = [
      { name = "order_id", type = "int" },
      { name = "customer_id", type = "string" },
      { name = "product_id", type = "string" },
      { name = "product_name", type = "string" },
      { name = "quantity", type = "int" },
      { name = "unit_price", type = "double" },
      { name = "total_amount", type = "double" },
      { name = "status", type = "string" },
      { name = "timestamp", type = "string" },
      { name = "region", type = "string" },
      { name = "payment_method", type = "string" }
    ]
  })

  tags = {
    Name = "${var.environment}-orders-value-schema"
  }
}

# MSK SCRAM Secret Association
resource "aws_msk_scram_secret_association" "msk_scram_secret" {
  cluster_arn     = aws_msk_cluster.msk_cluster.arn
  secret_arn_list = [aws_secretsmanager_secret.msk_scram_secret.arn]

  depends_on = [aws_secretsmanager_secret_version.msk_scram_secret]

  lifecycle {
    ignore_changes = [secret_arn_list]
  }
}

# Bastion Host Resources
# Data source to get EC2 Instance Connect CIDR block
data "http" "aws_ip_ranges" {
  count = var.create_bastion_host ? 1 : 0
  url   = "https://ip-ranges.amazonaws.com/ip-ranges.json"
}

locals {
  aws_ip_ranges = var.create_bastion_host ? jsondecode(data.http.aws_ip_ranges[0].response_body) : null
  ec2_instance_connect_cidr = var.create_bastion_host ? [
    for prefix in local.aws_ip_ranges.prefixes : prefix.ip_prefix
    if prefix.service == "EC2_INSTANCE_CONNECT" && prefix.region == var.aws_region
  ][0] : null
}

# Public Subnet for Bastion Host
resource "aws_subnet" "bastion_public_subnet" {
  count                   = var.create_bastion_host ? 1 : 0
  vpc_id                  = aws_vpc.msk_vpc.id
  cidr_block              = var.bastion_public_subnet_cidr
  availability_zone       = "${var.aws_region}${var.availability_zones[0]}"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.environment}-bastion-public-subnet"
    Type = "Public"
  }
}

# Route Table for Bastion Host Public Subnet
resource "aws_route_table" "bastion_public_rt" {
  count  = var.create_bastion_host ? 1 : 0
  vpc_id = aws_vpc.msk_vpc.id

  tags = {
    Name = "${var.environment}-bastion-public-rt"
  }
}

# Route for Internet Gateway
resource "aws_route" "bastion_public_route" {
  count                  = var.create_bastion_host && var.create_internet_gateway ? 1 : 0
  route_table_id         = aws_route_table.bastion_public_rt[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.msk_igw[0].id
}

# Route Table Association for Bastion Public Subnet
resource "aws_route_table_association" "bastion_public_rta" {
  count          = var.create_bastion_host ? 1 : 0
  subnet_id      = aws_subnet.bastion_public_subnet[0].id
  route_table_id = aws_route_table.bastion_public_rt[0].id
}

# Security Group for Bastion Host
resource "aws_security_group" "bastion_host_sg" {
  count       = var.create_bastion_host ? 1 : 0
  name        = "${var.environment}-bastion-host-sg"
  description = "Security group for bastion host with EC2 Instance Connect access"
  vpc_id      = aws_vpc.msk_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = concat(
      [local.ec2_instance_connect_cidr != null ? local.ec2_instance_connect_cidr : "0.0.0.0/0"],
      var.bastion_allowed_ssh_cidrs
    )
    description = "SSH access via EC2 Instance Connect and allowed CIDRs"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-bastion-host-sg"
  }
}

# EC2 Key Pair for Bastion Host
resource "aws_key_pair" "bastion_host_key" {
  count      = var.create_bastion_host && var.existing_bastion_key_pair_name == "" ? 1 : 0
  key_name   = "${var.environment}-migration-ssh-key"
  public_key = tls_private_key.bastion_host_key[0].public_key_openssh

  tags = {
    Name = "${var.environment}-migration-ssh-key"
  }
}

# TLS Private Key for Bastion Host
resource "tls_private_key" "bastion_host_key" {
  count     = var.create_bastion_host && var.existing_bastion_key_pair_name == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Store private key in AWS Systems Manager Parameter Store
resource "aws_ssm_parameter" "bastion_host_private_key" {
  count       = var.create_bastion_host && var.existing_bastion_key_pair_name == "" ? 1 : 0
  name        = "/ec2/keypair/${aws_key_pair.bastion_host_key[0].key_name}"
  description = "Private key for bastion host"
  type        = "SecureString"
  value       = tls_private_key.bastion_host_key[0].private_key_pem

  tags = {
    Name = "${var.environment}-bastion-host-private-key"
  }
}

# Save bastion host SSH key locally for SSH tunnel access
resource "local_file" "bastion_host_key" {
  count           = var.create_bastion_host && var.existing_bastion_key_pair_name == "" ? 1 : 0
  content         = tls_private_key.bastion_host_key[0].private_key_pem
  filename        = "${path.module}/ssh.pem"
  file_permission = "0400"
}

# Data source to get latest Amazon Linux 2023 AMI
data "aws_ssm_parameter" "amazon_linux_2023_ami" {
  count = var.create_bastion_host ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
}

# Bastion Host EC2 Instance
resource "aws_instance" "bastion_host" {
  count         = var.create_bastion_host ? 1 : 0
  ami           = data.aws_ssm_parameter.amazon_linux_2023_ami[0].value
  instance_type = var.bastion_instance_type
  subnet_id     = aws_subnet.bastion_public_subnet[0].id
  key_name      = var.existing_bastion_key_pair_name != "" ? var.existing_bastion_key_pair_name : aws_key_pair.bastion_host_key[0].key_name

  vpc_security_group_ids = [aws_security_group.bastion_host_sg[0].id]

  root_block_device {
    volume_size = 40
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    sudo yum install -y yum-utils
    sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
    sudo yum -y install terraform
    sudo yum install java-17-amazon-corretto-headless -y

    # Install k3s (lightweight Kubernetes for Gateway)
    curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

    # Install Helm
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

    # Install Vault (for Gateway credential store)
    curl -fsSL https://releases.hashicorp.com/vault/1.15.6/vault_1.15.6_linux_amd64.zip -o /tmp/vault.zip
    cd /tmp && unzip -o vault.zip && mv vault /usr/local/bin/ && rm vault.zip

    # Configure kubectl for ec2-user
    mkdir -p /home/ec2-user/.kube
    cp /etc/rancher/k3s/k3s.yaml /home/ec2-user/.kube/config
    chown ec2-user:ec2-user /home/ec2-user/.kube/config
    echo "export KUBECONFIG=/home/ec2-user/.kube/config" >> /home/ec2-user/.bashrc

    sudo su - ec2-user
    cd /home/ec2-user
    curl -O https://packages.confluent.io/archive/8.0/confluent-8.0.0.tar.gz
    tar xzf confluent-8.0.0.tar.gz
    rm -f confluent-8.0.0.tar.gz

    echo "export PATH=/home/ec2-user/confluent-8.0.0/bin:$PATH" >> /home/ec2-user/.bashrc

    curl -L -o kcp.tar.gz https://github.com/confluentinc/kcp/releases/download/v0.8.1/kcp_linux_amd64.tar.gz
    tar -xzf kcp.tar.gz
    chmod +x ./kcp/kcp
    sudo mv ./kcp/kcp /usr/local/bin/kcp

    # Clone migration workshops repository and copy clients folder
    git clone https://github.com/confluentinc/migration-workshops.git
    cp -r migration-workshops/hosted-kafka-to-enterprise-migration/clients ~/clients
  EOF
  )

  tags = {
    Name = "${var.environment}-migration-bastion-host"
  }
}

# ------------------------------------------------------
# Windows EC2 Instance
# ------------------------------------------------------


# Security Group for Windows EC2 Instance
resource "aws_security_group" "windows_sg" {
  name        = "windows-sg-${random_id.bucket_suffix.hex}"
  description = "Allow RDP traffic"
  vpc_id      = aws_vpc.msk_vpc.id

  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "windows-sg-${random_id.bucket_suffix.hex}"
  }
}

data "aws_ami" "windows" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2025-English-Full-Base-*"]
  }
}

resource "aws_instance" "windows_instance" {
  ami                    = data.aws_ami.windows.image_id
  instance_type          = "t3.large"
  key_name               = aws_key_pair.tf_key.key_name
  vpc_security_group_ids = [aws_security_group.windows_sg.id]
  subnet_id              = aws_subnet.bastion_public_subnet[0].id
  get_password_data      = true

  root_block_device {
    volume_size = 30
  }

  tags = {
    Name = "windows-instance-${random_id.bucket_suffix.hex}"
  }
}


resource "aws_key_pair" "tf_key" {
  key_name   = "key-${random_id.bucket_suffix.hex}"
  public_key = tls_private_key.rsa-4096-example.public_key_openssh
}

# RSA key of size 4096 bits
resource "tls_private_key" "rsa-4096-example" {
  algorithm = "RSA"
  rsa_bits  = 4096

}

resource "local_file" "tf_key" {
  content  = tls_private_key.rsa-4096-example.private_key_pem
  filename = "${path.module}/sshkey-${aws_key_pair.tf_key.key_name}"
  file_permission = "0400"
}



output "windows_bastion_ip" {
  description = "IP of the Windows bastion host"
  value       = aws_instance.windows_instance.public_ip
} 

output "windows_bastion_username" {
  description = "Username of the windows bastion host"
  value       = "Administrator"
} 

output "windows_bastion_password" {
  description = "Password of the windows bastion host"
  value       = nonsensitive(rsadecrypt(aws_instance.windows_instance.password_data, local_file.tf_key.content))
}

output "bastion_host_ip" {
  description = "Public IP of the Linux bastion host"
  value       = var.create_bastion_host ? aws_instance.bastion_host[0].public_ip : null
}

output "bastion_ssh_key_path" {
  description = "Path to the bastion host SSH private key"
  value       = var.create_bastion_host && var.existing_bastion_key_pair_name == "" ? local_file.bastion_host_key[0].filename : null
}

# ------------------------------------------------------
# MSK Connect Resources
# ------------------------------------------------------

# S3 Bucket for connector output (orders archive)
resource "aws_s3_bucket" "orders_archive_bucket" {
  count         = var.enable_connector_migration ? 1 : 0
  bucket        = "${var.environment}-orders-archive-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = {
    Name = "${var.environment}-orders-archive-bucket"
  }
}

resource "aws_s3_bucket_versioning" "orders_archive_bucket_versioning" {
  count  = var.enable_connector_migration ? 1 : 0
  bucket = aws_s3_bucket.orders_archive_bucket[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "orders_archive_bucket_encryption" {
  count  = var.enable_connector_migration ? 1 : 0
  bucket = aws_s3_bucket.orders_archive_bucket[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket for MSK Connect plugins
resource "aws_s3_bucket" "msk_connect_plugins_bucket" {
  count         = var.enable_connector_migration ? 1 : 0
  bucket        = "${var.environment}-msk-connect-plugins-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = {
    Name = "${var.environment}-msk-connect-plugins-bucket"
  }
}

# Download and upload Confluent S3 Sink Connector plugin
resource "null_resource" "download_s3_connector" {
  count = var.enable_connector_migration ? 1 : 0
  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ${path.module}/plugins
      if [ ! -f ${path.module}/plugins/confluentinc-kafka-connect-s3-10.5.13.zip ]; then
        curl -L -o ${path.module}/plugins/confluentinc-kafka-connect-s3-10.5.13.zip \
          "https://d2p6pa21dvn84.cloudfront.net/api/plugins/confluentinc/kafka-connect-s3/versions/10.5.13/confluentinc-kafka-connect-s3-10.5.13.zip"
      fi
    EOT
  }

  triggers = {
    plugin_file = "confluentinc-kafka-connect-s3-10.5.13.zip"
  }
}

resource "aws_s3_object" "s3_connector_plugin" {
  count  = var.enable_connector_migration ? 1 : 0
  bucket = aws_s3_bucket.msk_connect_plugins_bucket[0].id
  key    = "plugins/confluentinc-kafka-connect-s3-10.5.13.zip"
  source = "${path.module}/plugins/confluentinc-kafka-connect-s3-10.5.13.zip"

  depends_on = [null_resource.download_s3_connector]
}

# MSK Connect Custom Plugin
resource "aws_mskconnect_custom_plugin" "s3_sink_plugin" {
  count        = var.enable_connector_migration ? 1 : 0
  name         = "${var.environment}-s3-sink-connector-plugin"
  content_type = "ZIP"

  location {
    s3 {
      bucket_arn = aws_s3_bucket.msk_connect_plugins_bucket[0].arn
      file_key   = aws_s3_object.s3_connector_plugin[0].key
    }
  }

  depends_on = [aws_s3_object.s3_connector_plugin]
}

# MSK Connect Worker Configuration
resource "aws_mskconnect_worker_configuration" "s3_sink_worker_config" {
  count                   = var.enable_connector_migration ? 1 : 0
  name                    = "${var.environment}-s3-sink-worker-config"
  properties_file_content = <<PROPERTIES
key.converter=org.apache.kafka.connect.storage.StringConverter
value.converter=org.apache.kafka.connect.json.JsonConverter
value.converter.schemas.enable=false
PROPERTIES
}

# IAM Role for MSK Connect
resource "aws_iam_role" "msk_connect_role" {
  count = var.enable_connector_migration ? 1 : 0
  name  = "${var.environment}-msk-connect-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "kafkaconnect.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.environment}-msk-connect-role"
  }
}

# IAM Policy for MSK Connect to access S3
resource "aws_iam_role_policy" "msk_connect_s3_policy" {
  count = var.enable_connector_migration ? 1 : 0
  name  = "${var.environment}-msk-connect-s3-policy"
  role  = aws_iam_role.msk_connect_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.orders_archive_bucket[0].arn,
          "${aws_s3_bucket.orders_archive_bucket[0].arn}/*"
        ]
      }
    ]
  })
}

# IAM Policy for MSK Connect to access MSK cluster
resource "aws_iam_role_policy" "msk_connect_msk_policy" {
  count = var.enable_connector_migration ? 1 : 0
  name  = "${var.environment}-msk-connect-msk-policy"
  role  = aws_iam_role.msk_connect_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ClusterPermissions"
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:DescribeCluster",
          "kafka-cluster:AlterCluster",
          "kafka-cluster:DescribeClusterDynamicConfiguration"
        ]
        Resource = aws_msk_cluster.msk_cluster.arn
      },
      {
        Sid    = "TopicPermissions"
        Effect = "Allow"
        Action = [
          "kafka-cluster:CreateTopic",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:AlterTopic",
          "kafka-cluster:DeleteTopic",
          "kafka-cluster:DescribeTopicDynamicConfiguration",
          "kafka-cluster:AlterTopicDynamicConfiguration",
          "kafka-cluster:ReadData",
          "kafka-cluster:WriteData",
          "kafka-cluster:WriteDataIdempotently"
        ]
        Resource = "${replace(aws_msk_cluster.msk_cluster.arn, ":cluster/", ":topic/")}/*"
      },
      {
        Sid    = "GroupPermissions"
        Effect = "Allow"
        Action = [
          "kafka-cluster:AlterGroup",
          "kafka-cluster:DeleteGroup",
          "kafka-cluster:DescribeGroup"
        ]
        Resource = "${replace(aws_msk_cluster.msk_cluster.arn, ":cluster/", ":group/")}/*"
      },
      {
        Sid    = "TransactionalIdPermissions"
        Effect = "Allow"
        Action = [
          "kafka-cluster:DescribeTransactionalId",
          "kafka-cluster:AlterTransactionalId"
        ]
        Resource = "${replace(aws_msk_cluster.msk_cluster.arn, ":cluster/", ":transactional-id/")}/*"
      }
    ]
  })
}

# IAM Policy for MSK Connect to read Glue Schema Registry
# Only created when both connector and schema migration are enabled; the connector uses
# JsonConverter (schemas.enable=false) at runtime so this policy is purely defensive.
resource "aws_iam_role_policy" "msk_connect_glue_policy" {
  count = var.enable_connector_migration && var.enable_schema_migration ? 1 : 0
  name  = "${var.environment}-msk-connect-glue-policy"
  role  = aws_iam_role.msk_connect_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:GetRegistry",
          "glue:ListRegistries",
          "glue:GetSchema",
          "glue:ListSchemas",
          "glue:GetSchemaVersion",
          "glue:ListSchemaVersions",
          "glue:GetSchemaByDefinition"
        ]
        Resource = [
          aws_glue_registry.msk_schemas[0].arn,
          "${aws_glue_registry.msk_schemas[0].arn}/*",
          aws_glue_schema.orders_key[0].arn,
          aws_glue_schema.orders_value[0].arn
        ]
      }
    ]
  })
}

# IAM Policy for MSK Connect to write CloudWatch Logs
resource "aws_iam_role_policy" "msk_connect_logs_policy" {
  count = var.enable_connector_migration ? 1 : 0
  name  = "${var.environment}-msk-connect-logs-policy"
  role  = aws_iam_role.msk_connect_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:CreateLogGroup",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          aws_cloudwatch_log_group.msk_connect_log_group[0].arn,
          "${aws_cloudwatch_log_group.msk_connect_log_group[0].arn}:*"
        ]
      }
    ]
  })
}

# CloudWatch Log Group for MSK Connect
resource "aws_cloudwatch_log_group" "msk_connect_log_group" {
  count             = var.enable_connector_migration ? 1 : 0
  name              = "/aws/msk-connect/${var.environment}-orders-s3-sink"
  retention_in_days = 14

  tags = {
    Name = "${var.environment}-msk-connect-log-group"
  }
}

# MSK Connect Connector - S3 Sink for orders topic
resource "aws_mskconnect_connector" "orders_s3_sink" {
  count = var.enable_connector_migration ? 1 : 0
  name  = "${var.environment}-orders-s3-sink"

  kafkaconnect_version = "2.7.1"

  capacity {
    autoscaling {
      mcu_count        = 1
      min_worker_count = 1
      max_worker_count = 2

      scale_in_policy {
        cpu_utilization_percentage = 20
      }

      scale_out_policy {
        cpu_utilization_percentage = 80
      }
    }
  }

  connector_configuration = {
    "connector.class"                   = "io.confluent.connect.s3.S3SinkConnector"
    "tasks.max"                         = "1"
    "topics"                            = "orders"
    "s3.region"                         = var.aws_region
    "s3.bucket.name"                    = aws_s3_bucket.orders_archive_bucket[0].id
    "s3.part.size"                      = "5242880"
    "flush.size"                        = "3"
    "rotate.interval.ms"                = "60000"
    "storage.class"                     = "io.confluent.connect.s3.storage.S3Storage"
    "format.class"                      = "io.confluent.connect.s3.format.json.JsonFormat"
    "partitioner.class"                 = "io.confluent.connect.storage.partitioner.TimeBasedPartitioner"
    "partition.duration.ms"             = "3600000"
    "path.format"                       = "'year'=YYYY/'month'=MM/'day'=dd/'hour'=HH"
    "locale"                            = "en-US"
    "timezone"                          = "UTC"
    "schema.compatibility"              = "NONE"
    "key.converter"                     = "org.apache.kafka.connect.storage.StringConverter"
    "value.converter"                   = "org.apache.kafka.connect.json.JsonConverter"
    "value.converter.schemas.enable"    = "false"
    "errors.tolerance"                  = "all"
    "errors.log.enable"                 = "true"
    "errors.log.include.messages"       = "true"
    "behavior.on.null.values"           = "ignore"
  }

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = aws_msk_cluster.msk_cluster.bootstrap_brokers_sasl_iam
      vpc {
        security_groups = [aws_security_group.msk_cluster_sg.id]
        subnets         = aws_subnet.msk_private_subnets[*].id
      }
    }
  }

  kafka_cluster_client_authentication {
    authentication_type = "IAM"
  }

  kafka_cluster_encryption_in_transit {
    encryption_type = "TLS"
  }

  plugin {
    custom_plugin {
      arn      = aws_mskconnect_custom_plugin.s3_sink_plugin[0].arn
      revision = aws_mskconnect_custom_plugin.s3_sink_plugin[0].latest_revision
    }
  }

  log_delivery {
    worker_log_delivery {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk_connect_log_group[0].name
      }
    }
  }

  service_execution_role_arn = aws_iam_role.msk_connect_role[0].arn

  worker_configuration {
    arn      = aws_mskconnect_worker_configuration.s3_sink_worker_config[0].arn
    revision = aws_mskconnect_worker_configuration.s3_sink_worker_config[0].latest_revision
  }

  depends_on = [
    aws_msk_cluster.msk_cluster,
    aws_mskconnect_custom_plugin.s3_sink_plugin,
    aws_mskconnect_worker_configuration.s3_sink_worker_config,
    aws_iam_role_policy.msk_connect_s3_policy,
    aws_iam_role_policy.msk_connect_msk_policy,
    aws_iam_role_policy.msk_connect_logs_policy,
    aws_msk_scram_secret_association.msk_scram_secret
  ]
}

# MSK Connect Outputs
output "msk_connect_connector_arn" {
  description = "ARN of the MSK Connect connector"
  value       = var.enable_connector_migration ? aws_mskconnect_connector.orders_s3_sink[0].arn : null
}

output "msk_connect_connector_name" {
  description = "Name of the MSK Connect connector"
  value       = var.enable_connector_migration ? aws_mskconnect_connector.orders_s3_sink[0].name : null
}

output "orders_archive_bucket_name" {
  description = "S3 bucket name for orders archive"
  value       = var.enable_connector_migration ? aws_s3_bucket.orders_archive_bucket[0].id : null
}

output "msk_connect_log_group" {
  description = "CloudWatch log group for MSK Connect"
  value       = var.enable_connector_migration ? aws_cloudwatch_log_group.msk_connect_log_group[0].name : null
}

