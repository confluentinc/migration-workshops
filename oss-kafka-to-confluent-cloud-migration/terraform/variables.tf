variable "aws_region" {
  description = "AWS region for the source environment. The KCP-generated Confluent Cloud target is created in the same region."
  type        = string
  default     = "us-west-2"
}

variable "name_prefix" {
  description = "Prefix for the names of the AWS resources this workshop creates."
  type        = string
  default     = "oss-migration"
}

variable "vpc_cidr" {
  description = "CIDR block for the workshop VPC. Must be a /16: subnets are carved out with cidrsubnet(vpc_cidr, 8, n)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "kafka_instance_type" {
  description = "EC2 instance type for the single-node open-source Kafka source cluster."
  type        = string
  default     = "t3.small"
}

variable "bastion_instance_type" {
  description = "EC2 instance type for the bastion (k3s + Gateway + KCP + clients). t3.large is the smallest that runs the Gateway comfortably."
  type        = string
  default     = "t3.large"
}

variable "allowed_ssh_cidrs" {
  description = "Extra CIDRs allowed to SSH to the bastion (e.g. [\"203.0.113.10/32\"]). EC2 Instance Connect from the AWS Console always works; add your IP only if you want SSH from your laptop (needed for the optional KCP UI tunnel)."
  type        = list(string)
  default     = []
}
