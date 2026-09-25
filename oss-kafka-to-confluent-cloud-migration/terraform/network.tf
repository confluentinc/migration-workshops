data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

# Public subnet: the bastion (EC2 Instance Connect) and the NAT gateway.
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name_prefix}-public"
  }
}

# Private subnet: the Kafka broker (no public IP) and, later, the KCP-generated NLB and
# cluster-link provisioning instance.
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${var.name_prefix}-private"
  }
}

# Outbound-only internet for the private subnet (package and Kafka downloads at boot).
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.name_prefix}-nat"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "${var.name_prefix}-nat"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.name_prefix}-public"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.name_prefix}-private"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# S3 traffic from the subnets stays inside AWS. The workshop bucket (workshop_bundle.tf)
# only serves requests that arrive through this endpoint.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.public.id, aws_route_table.private.id]

  tags = {
    Name = "${var.name_prefix}-s3"
  }
}

# Private DNS for the broker, resolvable only inside the VPC.
resource "aws_route53_zone" "internal" {
  name          = local.private_zone
  force_destroy = true

  vpc {
    vpc_id = aws_vpc.main.id
  }
}

resource "aws_route53_record" "kafka" {
  zone_id = aws_route53_zone.internal.zone_id
  name    = local.kafka_host
  type    = "A"
  ttl     = 60
  records = [aws_instance.kafka.private_ip]
}

# EC2 Instance Connect (the browser SSH in the AWS Console) connects from these ranges.
data "http" "aws_ip_ranges" {
  url = "https://ip-ranges.amazonaws.com/ip-ranges.json"
}

locals {
  ec2_instance_connect_cidrs = [
    for prefix in jsondecode(data.http.aws_ip_ranges.response_body).prefixes : prefix.ip_prefix
    if prefix.service == "EC2_INSTANCE_CONNECT" && prefix.region == var.aws_region
  ]
}

resource "aws_security_group" "bastion" {
  name_prefix = "${var.name_prefix}-bastion-"
  description = "Workshop bastion: SSH from EC2 Instance Connect and allowed CIDRs only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = concat(local.ec2_instance_connect_cidrs, var.allowed_ssh_cidrs)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-bastion"
  }
}

resource "aws_security_group" "kafka" {
  name_prefix = "${var.name_prefix}-kafka-"
  description = "Workshop Kafka broker: reachable only from inside the VPC"
  vpc_id      = aws_vpc.main.id

  # SASL_SSL listener: the bastion (clients, Gateway, KCP) and the KCP-generated NLB that
  # fronts the broker for Confluent Cloud's external outbound cluster link.
  ingress {
    description = "Kafka SASL_SSL"
    from_port   = local.kafka_port
    to_port     = local.kafka_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Read-only Jolokia agent, polled by `kcp scan clusters --metrics jolokia`.
  ingress {
    description     = "Jolokia (KCP metrics)"
    from_port       = 8778
    to_port         = 8778
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-kafka"
  }
}

# For the short-lived EC2 instance that the KCP-generated migration-infra Terraform
# launches to create the cluster link through the Enterprise cluster's private REST
# endpoint (STEP-2). Outbound only.
resource "aws_security_group" "link_provisioner" {
  name_prefix = "${var.name_prefix}-link-provisioner-"
  description = "KCP cluster-link provisioning instance: outbound only"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-link-provisioner"
  }
}
