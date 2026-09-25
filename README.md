# migration-workshops

Hands-on workshops for migrating to Confluent Cloud using the KCP CLI, Cluster Linking, and the
Confluent Cloud Gateway.

| Workshop | Source | Where it runs |
| :-- | :-- | :-- |
| [hosted-kafka-to-enterprise-migration](./hosted-kafka-to-enterprise-migration) | Amazon MSK | AWS (Terraform-provisioned MSK + bastion) |
| [oss-kafka-to-confluent-cloud-migration](./oss-kafka-to-confluent-cloud-migration) | Open-source Apache Kafka | AWS (Terraform-provisioned EC2 broker + bastion), migrating to an Enterprise cluster over PrivateLink |

Both follow the same six-stage framework: Setup → Discover/Plan → Provision → Migrate Data →
Migrate Clients → Cleanup.

This repository is part of the Confluent organization on GitHub.
It is public and open to contributions from the community.

Please see the LICENSE file for contribution terms.
Please see the CHANGELOG.md for details of recent updates.
