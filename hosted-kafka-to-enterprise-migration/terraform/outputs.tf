output "msk_cluster_arn" {
  description = "ARN of the MSK cluster"
  value       = aws_msk_cluster.msk_cluster.arn
}

output "msk_cluster_name" {
  description = "Name of the MSK cluster"
  value       = aws_msk_cluster.msk_cluster.cluster_name
}

output "msk_bootstrap_servers" {
  description = "Bootstrap servers for the MSK cluster"
  value       = aws_msk_cluster.msk_cluster.bootstrap_brokers_tls
}

output "msk_bootstrap_servers_sasl_scram" {
  description = "Bootstrap servers for SASL/SCRAM authentication"
  value       = aws_msk_cluster.msk_cluster.bootstrap_brokers_sasl_scram
}

# Note: Kafka 4.0+ uses KRaft mode - no Zookeeper connection strings available
# KRaft mode eliminates the need for Zookeeper and provides better scalability and performance

output "kafka_mode" {
  description = "Kafka coordination mode (KRaft for 4.0+, Zookeeper for older versions)"
  value       = "KRaft"
}

output "vpc_id" {
  description = "ID of the VPC where MSK cluster is deployed"
  value       = aws_vpc.msk_vpc.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.msk_vpc.cidr_block
}

output "internet_gateway_id" {
  description = "ID of the internet gateway (if created)"
  value       = var.create_internet_gateway ? aws_internet_gateway.msk_igw[0].id : null
}

output "msk_subnet_ids" {
  description = "IDs of the subnets where MSK cluster is deployed (private subnets for private access)"
  value       = aws_subnet.msk_private_subnets[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.msk_private_subnets[*].id
}



output "msk_security_group_id" {
  description = "Security group ID for MSK cluster"
  value       = aws_security_group.msk_cluster_sg.id
}

output "msk_client_security_group_id" {
  description = "Security group ID for MSK clients"
  value       = aws_security_group.msk_client_sg.id
}



output "msk_configuration_arn" {
  description = "ARN of the MSK configuration"
  value       = aws_msk_configuration.msk_config.arn
}

output "msk_scram_secret_arn" {
  description = "ARN of the SCRAM secret for authentication"
  value       = aws_secretsmanager_secret.msk_scram_secret.arn
}

output "msk_kms_key_id" {
  description = "KMS key ID used for MSK encryption"
  value       = aws_kms_key.msk_kms_key.key_id
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name for MSK logs"
  value       = var.enable_logging ? aws_cloudwatch_log_group.msk_log_group[0].name : null
}

output "s3_logs_bucket_name" {
  description = "S3 bucket name for MSK logs"
  value       = var.enable_logging ? aws_s3_bucket.msk_logs_bucket[0].id : null
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

# Connection information for Confluent Cluster Linking
output "confluent_connection_info" {
  description = "Connection information for Confluent Cluster Linking (Kafka 4.0+ with KRaft mode)"
  value = {
    bootstrap_servers = aws_msk_cluster.msk_cluster.bootstrap_brokers_sasl_scram
    cluster_name      = aws_msk_cluster.msk_cluster.cluster_name
    security_protocol = "SASL_SSL"
    sasl_mechanism    = "SCRAM-SHA-512"
    ssl_ca_location   = "/etc/ssl/certs/ca-certificates.crt"
    secret_arn        = aws_secretsmanager_secret.msk_scram_secret.arn
    kafka_mode        = "KRaft"
  }
  sensitive = false
}

output "connection_commands" {
  description = "Commands to connect to the MSK cluster"
  value = {
    describe_cluster = "aws kafka describe-cluster --cluster-arn ${aws_msk_cluster.msk_cluster.arn}"
    get_bootstrap_brokers = "aws kafka get-bootstrap-brokers --cluster-arn ${aws_msk_cluster.msk_cluster.arn}"
    get_scram_secret = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.msk_scram_secret.arn}"
  }
}
