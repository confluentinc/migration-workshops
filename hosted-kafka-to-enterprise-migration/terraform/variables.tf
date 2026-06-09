variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}



variable "availability_zones" {
  description = "Availability zones for the VPC"
  type        = list(string)
  default     = ["a", "b", "c"]
}

variable "kafka_version" {
  description = "Kafka version for MSK cluster (4.0.x.kraft uses KRaft, no Zookeeper)"
  type        = string
  default     = "3.9.x.kraft"
}

variable "number_of_broker_nodes" {
  description = "Number of broker nodes per AZ"
  type        = number
  default     = 1
}

variable "cluster_name" {
  description = "Name of the MSK cluster"
  type        = string
  default     = "msk-migration-cluster"
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access MSK cluster"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "enable_logging" {
  description = "Enable logging for MSK cluster"
  type        = bool
  default     = true
}

variable "create_internet_gateway" {
  description = "Whether to create an internet gateway for the VPC"
  type        = bool
  default     = true
}

variable "msk_username" {
  description = "MSK SASL username for SCRAM authentication"
  type        = string
  default     = "msk-user"
}

variable "msk_password" {
  description = "MSK SASL password for SCRAM authentication"
  type        = string
  sensitive   = true
}

# Bastion Host Variables
variable "create_bastion_host" {
  description = "Whether to create a bastion host for MSK access"
  type        = bool
  default     = true
}

variable "bastion_instance_type" {
  description = "Instance type for the bastion host (t3.large recommended for k3s + CFK + Gateway)"
  type        = string
  default     = "t3.large"
}

variable "bastion_public_subnet_cidr" {
  description = "CIDR block for the bastion host public subnet"
  type        = string
  default     = "10.0.100.0/24"
}

variable "existing_bastion_key_pair_name" {
  description = "Existing EC2 key pair name to use for bastion host (if provided, new key pair will not be created)"
  type        = string
  default     = ""
}

variable "bastion_allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH to the bastion host. Defaults to 0.0.0.0/0 (open) for workshop convenience."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "broker_node_instance_type" {
  description = "Instance type for MSK broker nodes"
  type        = string
  default     = "kafka.m5.large"
}

variable "broker_node_storage_size" {
  description = "Storage size for MSK broker nodes in GB"
  type        = number
  default     = 100
}

variable "enable_monitoring" {
  description = "Enable enhanced monitoring for MSK cluster"
  type        = bool
  default     = true
}

# Optional migration tracks (opt-in)
variable "enable_acl_migration" {
  description = "Enable the ACL migration track in workshop docs/scripts (no Terraform resources gated)."
  type        = bool
  default     = false
}

variable "enable_schema_migration" {
  description = "Provision AWS Glue Schema Registry + orders Avro schemas for the schema-migration track."
  type        = bool
  default     = false
}

variable "enable_connector_migration" {
  description = "Provision MSK Connect S3-sink connector (plugin bucket, IAM role, log group, archive bucket, connector) for the connector-migration track."
  type        = bool
  default     = false
}
