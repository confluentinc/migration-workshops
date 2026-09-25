# A private CA for the workshop and a broker certificate for kafka.oss-workshop.internal.
# The bastion trusts the CA system-wide, and STEP-2 adds it to the cluster link's
# truststore, so every TLS connection to the broker is verified.
#
# Workshop-grade: the private keys live in Terraform state and in the broker's user data.

resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem       = tls_private_key.ca.private_key_pem
  is_ca_certificate     = true
  validity_period_hours = 24 * 90

  subject {
    common_name  = "OSS Kafka Migration Workshop CA"
    organization = "Confluent migration workshop"
  }

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "digital_signature",
  ]
}

resource "tls_private_key" "kafka" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "kafka" {
  private_key_pem = tls_private_key.kafka.private_key_pem
  dns_names       = [local.kafka_host]

  subject {
    common_name  = local.kafka_host
    organization = "Confluent migration workshop"
  }
}

resource "tls_locally_signed_cert" "kafka" {
  cert_request_pem      = tls_cert_request.kafka.cert_request_pem
  ca_private_key_pem    = tls_private_key.ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.ca.cert_pem
  validity_period_hours = 24 * 90

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
  ]
}

# SSH key for the bastion (EC2 Instance Connect works without it).
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "bastion" {
  key_name_prefix = "${var.name_prefix}-bastion-"
  public_key      = tls_private_key.ssh.public_key_openssh
}

resource "local_sensitive_file" "ssh_private_key" {
  content         = tls_private_key.ssh.private_key_openssh
  filename        = "${path.module}/ssh.pem"
  file_permission = "0400"
}
