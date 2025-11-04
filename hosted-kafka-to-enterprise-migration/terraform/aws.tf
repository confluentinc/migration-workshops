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

  # Kafka broker communication - SASL_SSL only
  ingress {
    from_port   = 9096
    to_port     = 9096
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Kafka SASL_SSL (SCRAM)"
  }

  # KRaft Controller communication (for internal cluster communication)
  ingress {
    from_port   = 9093
    to_port     = 9093
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "KRaft Controller"
  }

  # JMX monitoring ports (optional, for monitoring)
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
  count  = var.enable_logging ? 1 : 0
  bucket = "${var.environment}-msk-logs-${random_id.bucket_suffix.hex}"

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

  # Authentication configuration - SASL SCRAM only
  client_authentication {
    unauthenticated = false
    sasl {
      scram = true
      iam   = false
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

  # Monitoring configuration
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

# MSK SCRAM Secret Association
resource "aws_msk_scram_secret_association" "msk_scram_secret" {
  cluster_arn     = aws_msk_cluster.msk_cluster.arn
  secret_arn_list = [aws_secretsmanager_secret.msk_scram_secret.arn]

  depends_on = [aws_secretsmanager_secret_version.msk_scram_secret]
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
    cidr_blocks = [local.ec2_instance_connect_cidr != null ? local.ec2_instance_connect_cidr : "0.0.0.0/0"]
    description = "SSH access via EC2 Instance Connect"
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

  user_data = base64encode(<<-EOF
    #!/bin/bash
    sudo yum install -y yum-utils
    sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
    sudo yum -y install terraform
    sudo yum install java-17-amazon-corretto-headless -y

    sudo su - ec2-user
    cd /home/ec2-user
    curl -O https://packages.confluent.io/archive/8.0/confluent-8.0.0.tar.gz
    tar xzf confluent-8.0.0.tar.gz

    echo "export PATH=/home/ec2-user/confluent-8.0.0/bin:$PATH" >> /home/ec2-user/.bashrc

    curl -L -o kcp https://github.com/confluentinc/kcp/releases/download/v0.4.3/kcp_linux_amd64
    chmod +x kcp
    sudo mv kcp /usr/local/bin/

    # Clone migration workshops repository and copy clients folder
    git clone https://github.com/confluentinc/migration-workshops.git
    cp -r migration-workshops/hosted-kafka-to-enterprise-migration/clients ~/clients
  EOF
  )

  tags = {
    Name = "${var.environment}-migration-bastion-host"
  }
}
