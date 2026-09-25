terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# AWS credentials come from your environment (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY /
# AWS_SESSION_TOKEN, or an AWS CLI profile).
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "oss-kafka-migration-workshop"
      ManagedBy = "Terraform"
    }
  }
}
