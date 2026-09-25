output "aws_region" {
  description = "AWS region of the source environment."
  value       = var.aws_region
}

output "vpc_id" {
  description = "Workshop VPC (the KCP target-infra and migration-infra assets are created in it)."
  value       = aws_vpc.main.id
}

output "bastion_instance_id" {
  description = "Bastion instance: open it in the EC2 Console and use Connect > EC2 Instance Connect."
  value       = aws_instance.bastion.id
}

output "bastion_public_ip" {
  description = "Public IP of the bastion."
  value       = aws_instance.bastion.public_ip
}

output "ssh_command" {
  description = "SSH to the bastion from this directory (requires your IP in allowed_ssh_cidrs)."
  value       = "ssh -i ${local_sensitive_file.ssh_private_key.filename} ec2-user@${aws_instance.bastion.public_ip}"
}

output "kafka_bootstrap" {
  description = "Source cluster bootstrap (SASL_SSL, SCRAM-SHA-512), resolvable only inside the VPC."
  value       = "${local.kafka_host}:${local.kafka_port}"
}

output "kafka_instance_id" {
  description = "Source broker instance (private; reachable from the Console via Session Manager)."
  value       = aws_instance.kafka.id
}

output "kafka_private_ip" {
  description = "Private IP of the source broker."
  value       = aws_instance.kafka.private_ip
}

output "private_link_subnet_cidrs" {
  description = "Free CIDRs to pass to `kcp create-asset target-infra --subnet-cidrs`."
  value       = local.private_link_subnet_cidrs
}

output "workshop_bundle_url" {
  description = "The workshop scripts the bastion unpacks at boot; readable only from inside the VPC."
  value       = "https://${aws_s3_bucket.workshop.bucket_regional_domain_name}/${aws_s3_object.workshop.key}"
}

output "workshop_ca_cert_pem" {
  description = "Workshop CA certificate that signs the broker's certificate."
  value       = tls_self_signed_cert.ca.cert_pem
}
