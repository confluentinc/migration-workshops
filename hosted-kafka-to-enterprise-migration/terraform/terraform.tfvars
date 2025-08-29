aws_region     = "us-west-2"
environment    = "dev"
cluster_name   = "msk-migration-cluster"
kafka_version  = "4.0.x.kraft"

# Network configuration
vpc_cidr            = "10.0.0.0/16"
availability_zones  = ["a", "b", "c"]
allowed_cidr_blocks = ["10.0.0.0/16"]  # VPC-only access for private MSK cluster

# MSK configuration
broker_node_instance_type = "kafka.m5.large"
broker_node_storage_size  = 100
number_of_broker_nodes    = 1

# MSK Authentication
msk_username = "msk-user"
msk_password = "ChangeMe123!"

# Features
enable_logging    = true
enable_monitoring = true
