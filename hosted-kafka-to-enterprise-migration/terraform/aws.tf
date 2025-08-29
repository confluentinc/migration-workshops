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
