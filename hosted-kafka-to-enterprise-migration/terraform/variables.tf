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
  default     = "4.0.x.kraft"
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

variable "enable_monitoring" {
  description = "Enable enhanced monitoring for MSK cluster"
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
