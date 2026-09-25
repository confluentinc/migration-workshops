locals {
  # The broker's DNS name, served by a Route 53 private hosted zone. It is the broker's
  # advertised listener, the SAN on its certificate, and the host the KCP-generated
  # external outbound cluster link resolves on the Confluent Cloud side, so it is fixed
  # (clients/, kcp/ and gateway/ all reference it).
  private_zone = "oss-workshop.internal"
  kafka_host   = "kafka.${local.private_zone}"
  kafka_port   = 9092

  # Workshop SCRAM user on the source cluster (also in clients/env.oss, clients/env.gateway
  # and kcp/apache-kafka-credentials.yaml).
  scram_username = "orders-app"
  scram_password = "ChangeMe123!"

  public_subnet_cidr  = cidrsubnet(var.vpc_cidr, 8, 1)
  private_subnet_cidr = cidrsubnet(var.vpc_cidr, 8, 2)
  # Reserved for the subnets `kcp create-asset target-infra` creates for the Confluent
  # Cloud PrivateLink endpoint (STEP-2). Nothing in this module uses them.
  private_link_subnet_cidrs = [for n in [10, 20, 30] : cidrsubnet(var.vpc_cidr, 8, n)]

  # Pinned downloads, verified against these checksums in the instances' user data.
  kafka_version   = "3.9.0"
  kafka_sha512    = "5324c1f44d4c84ea469712c2cc3d2d15545c3716edbb5353722df9c661fcc78b031fcf07d1c4f0309c5fdb32686665dfb0cffe55210cd3a1fe2a370538cb4e6d"
  jolokia_version = "2.6.2"
  jolokia_sha256  = "e2de9dac0eb30cd6675e1d9d12cbc62a45c1fb0f80777810456af6f3f74976e8"
  kcp_version     = "0.9.2"
  kcp_sha256      = "ef49cd5bb90f16664d32dbc40a1930df7212ad1a5e0d1c5234d3e77c76178a46"
  vault_version   = "1.15.6"
  vault_sha256    = "e5286f2f66a76972d1dd60a9cfb79e9e571c39a4531e89ac0b23a6a9147e6ee9"
}
