data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
}

data "aws_partition" "current" {}

# Lets you open a shell on the private broker from the AWS Console (Session Manager)
# for troubleshooting; the workshop itself never logs in to it.
resource "aws_iam_role" "kafka" {
  name_prefix = "${var.name_prefix}-kafka-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "kafka_ssm" {
  role       = aws_iam_role.kafka.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "kafka" {
  name_prefix = "${var.name_prefix}-kafka-"
  role        = aws_iam_role.kafka.name
}

# The source cluster: open-source Apache Kafka, single KRaft node, private subnet only.
resource "aws_instance" "kafka" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.kafka_instance_type
  subnet_id                   = aws_subnet.private.id
  vpc_security_group_ids      = [aws_security_group.kafka.id]
  iam_instance_profile        = aws_iam_instance_profile.kafka.name
  associate_public_ip_address = false

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/templates/kafka-setup.sh.tftpl", {
    kafka_host      = local.kafka_host
    kafka_port      = local.kafka_port
    kafka_version   = local.kafka_version
    kafka_sha512    = local.kafka_sha512
    jolokia_version = local.jolokia_version
    jolokia_sha256  = local.jolokia_sha256
    scram_username  = local.scram_username
    scram_password  = local.scram_password
    broker_key_pem  = tls_private_key.kafka.private_key_pem_pkcs8
    broker_cert_pem = tls_locally_signed_cert.kafka.cert_pem
    ca_cert_pem     = tls_self_signed_cert.ca.cert_pem
  })
  user_data_replace_on_change = true

  tags = {
    Name = "${var.name_prefix}-kafka"
  }

  # User data only runs at first boot, so a later change must not touch the running broker
  # (and its data) mid-workshop. Rebuild it deliberately with -replace=aws_instance.kafka.
  lifecycle {
    ignore_changes = [ami, user_data]
  }

  # Boot only once the private subnet can reach the internet for its downloads.
  depends_on = [aws_route_table_association.private]
}

# The migration control plane inside the VPC: Gateway (k3s), KCP, Vault, clients.
resource "aws_instance" "bastion" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.bastion_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  key_name               = aws_key_pair.bastion.key_name

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size = 40
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/templates/bastion-setup.sh.tftpl", {
    aws_region                = var.aws_region
    vpc_id                    = aws_vpc.main.id
    kafka_host                = local.kafka_host
    kafka_port                = local.kafka_port
    kafka_private_ip          = aws_instance.kafka.private_ip
    kafka_subnet_id           = aws_subnet.private.id
    link_provisioner_sg_id    = aws_security_group.link_provisioner.id
    private_link_subnet_cidrs = join(",", local.private_link_subnet_cidrs)
    scram_username            = local.scram_username
    scram_password            = local.scram_password
    ca_cert_pem               = tls_self_signed_cert.ca.cert_pem
    kafka_version             = local.kafka_version
    kafka_sha512              = local.kafka_sha512
    kcp_version               = local.kcp_version
    kcp_sha256                = local.kcp_sha256
    vault_version             = local.vault_version
    vault_sha256              = local.vault_sha256
    workshop_bundle_url       = "https://${aws_s3_bucket.workshop.bucket_regional_domain_name}/${aws_s3_object.workshop.key}"
    workshop_bundle_sha256    = data.archive_file.workshop.output_sha256
  })
  user_data_replace_on_change = true

  tags = {
    Name = "${var.name_prefix}-bastion"
  }

  # The bastion holds the KCP-generated Terraform state for the Confluent Cloud resources, so
  # a later change to its user data (e.g. an updated script bundle) must never replace it
  # implicitly. Rebuild it deliberately with -replace=aws_instance.bastion.
  lifecycle {
    ignore_changes = [ami, user_data]
  }

  # The bundle must be uploaded and readable through the S3 endpoint before first boot.
  depends_on = [aws_route_table_association.public, aws_s3_object.workshop, aws_s3_bucket_policy.workshop]
}
