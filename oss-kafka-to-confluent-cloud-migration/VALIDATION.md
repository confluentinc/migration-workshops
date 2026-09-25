# Validation checklist (end-to-end run)

The workshop's code and docs are complete and internally consistent, but "done" also requires
one **end-to-end run in a real AWS + Confluent Cloud account** — **setup → replication →
cutover → cleanup** — with the assertions below checked and the terminal output recorded. That
run provisions paid resources, so it is the remaining step before this workshop is used live.

## Prerequisites for the run

- An AWS account and credentials; a Confluent Cloud account and a Cloud resource management API
  key; Terraform 1.5+ on the laptop.
- Nothing needs to be pushed first: `terraform apply` bundles the scripts from the local checkout
  (`terraform/workshop_bundle.tf`) and the bastion downloads them through the VPC's S3 endpoint.

## Assertions

### 1. Setup & discovery (STEP-0 / STEP-1)

- [ ] `terraform apply` succeeds; the broker has **no public IP**, and its security group admits
      9092 only from the VPC CIDR and 8778 only from the bastion's security group.
- [ ] On the bastion, `cloud-init status --wait` prints `status: done`, and `workshop.env` and
      `ca.pem` exist in `~/oss-workshop`.
- [ ] `python3 kafka_config.py --check` (with `env.oss`) connects over SASL_SSL **with
      certificate verification** and lists `orders`.
- [ ] `gateway/setup_gateway.sh` deploys the Gateway; the producer and consumer flow through
      `localhost:9595` to the broker over SASL_SSL (`oss-tls` truststore).
- [ ] `kcp scan clusters --source-type apache-kafka --metrics jolokia ...` succeeds **without**
      `insecure_skip_tls_verify` (verifying via `ca_cert`) and records `orders`,
      `orders-consumer-group` and non-zero `BytesInPerSec` / `MessagesInPerSec` in
      `kcp-state.json`.
- [ ] The Jolokia agent refuses non-read operations (e.g. an `exec` request returns a
      permission error).

### 2. Provision & replication (STEP-2 / STEP-3)

- [ ] `kcp create-asset target-infra ... --cluster-type enterprise --needs-private-link
      --prevent-destroy=false` generates Terraform that applies cleanly; the bastion resolves the
      cluster's private bootstrap and REST hostnames.
- [ ] `kcp create-asset migration-infra --type 2 --source-type apache-kafka ...` generates
      Terraform; after `kcp/prepare_migration_infra.sh`, `terraform plan` shows the broker's
      real subnet and IP, and NLB / target group names within AWS's 32-character limit.
- [ ] `terraform -chdir=migration-infra apply` succeeds, and within a few minutes
      `kcp/cc_status.sh link` shows `ACTIVE` / `NO_ERROR`.
- [ ] `kcp/cc_status.sh configs` shows `ssl.truststore.type=PEM`,
      `consumer.offset.sync.enable=true`, `consumer.offset.sync.ms=5000`, and the
      `orders-consumer-group` filter (i.e. Confluent Cloud accepted the PEM truststore and the
      offset-sync settings at link creation).
- [ ] `kcp create-asset migrate-topics --cc-type commercial ...` applies; the `orders` mirror is
      `ACTIVE` and its lag trends to zero.
- [ ] **`orders-consumer-group` appears on the destination** (`kcp/cc_status.sh groups`) before
      the cutover.
- [ ] `gateway/configure_gateway_target.sh` registers the SCRAM user and renders the switchover
      CR.

### 3. Cutover (STEP-4)

- [ ] `kcp migration init --migration-yaml kcp/gateway-migration.yaml` reports the Gateway CRs
      validated (secret references present), the cluster link validated with `orders` active, and
      `consumer.offset.sync.enable=true`.
- [ ] `kcp migration execute` completes every step — lag check, fence (derived from the live CR),
      offset-sync drain and pause, promote, switchover, offset-sync restore — and the
      producer/consumer resume against Confluent Cloud after the brief fenced window, **without
      restart or reconfiguration**.
- [ ] **Delivered order IDs:** the producer's shutdown summary reconciles against what the
      consumer reads on Confluent Cloud. Record any duplicates (the producer is at-least-once)
      and confirm there is no silent loss.
- [ ] **Consumer offsets:** the consumer resumes from its committed position — no full reprocess
      and no gap — confirming offset sync worked.
- [ ] **Interrupted-cutover recovery** behaves as documented (STEP-4): re-running `execute`
      resumes (re-fencing first), and re-applying the init-state CR before promotion restores
      traffic to the broker.

### 4. Cleanup (STEP-5)

- [ ] `./cleanup.sh` on the bastion prints "Bastion cleanup complete" and exits **0** only when
      `migration-infra/` and `target_infra/` are empty, and exits **non-zero** otherwise.
- [ ] `terraform destroy` on the laptop then removes the VPC without dependency errors.
- [ ] The Confluent Cloud Console shows no workshop environment; the AWS Console shows no
      workshop VPC, NLB, VPC endpoint or endpoint service.

## Checked before the end-to-end run

Verified locally (no AWS / Confluent Cloud account needed):

- `terraform validate` / `fmt` on `terraform/`, and both user-data scripts render under EC2's
  16 KB limit.
- The broker user data runs to completion on Amazon Linux 2023 (in a container): Kafka comes up
  with the PEM keystore on a SASL_SSL listener advertised as `kafka.oss-workshop.internal`, the
  `orders` topic exists, and Jolokia serves reads but refuses `exec`.
- From a second Amazon Linux 2023 container running the bastion user data: KCP `v0.9.2` scans
  the cluster with Jolokia metrics, verifying the broker via `ca_cert` (a wrong `ca_cert` fails
  with `x509: certificate signed by unknown authority`), and records `orders-consumer-group`;
  `kcp report metrics` shows the live throughput; the Python producer/consumer work over
  verified SASL_SSL.
- KCP `v0.9.2` generates `target-infra` (with `--prevent-destroy=false` honored), Type 2
  `migration-infra`, and `migrate-topics --topics-include orders` (just `orders`; without the
  flag it also emits `__consumer_offsets`). `kcp/prepare_migration_infra.sh` produces a link
  payload that renders to valid JSON through Terraform's `templatefile`, its `aws_kafka_brokers`
  override wins over KCP's `inputs.auto.tfvars`, and `terraform validate` passes.
- On a k3d cluster: `gateway/setup_gateway.sh` brings the Gateway up with the `oss-tls`
  truststore and the producer/consumer work through `localhost:9595` over SASL_SSL passthrough;
  `gateway/configure_gateway_target.sh` (Vault and `kafka-configs.sh` stubbed) creates the
  secrets and applies the init-state CR; then `kcp migration init --migration-yaml
  kcp/gateway-migration.yaml`, against a mock of the Confluent Cloud REST endpoints, validates
  the Gateway CRs (4 secret references), the mirror topics and offset sync, and registers
  `oss-to-cc`. An unset `${VAR}` fails naming the variable.
- `kcp/write_target_env.sh` (against stand-in Terraform outputs) and `kcp/cc_status.sh` (against
  a mock of the Confluent Cloud REST v3 responses).
