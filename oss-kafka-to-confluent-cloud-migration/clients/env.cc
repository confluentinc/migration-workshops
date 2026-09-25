# Confluent Cloud Enterprise cluster, direct connection from the bastion over PrivateLink.
# The endpoint and API key come from target.env, which kcp/write_target_env.sh generates
# from the KCP target-infra outputs in STEP-2 (it is gitignored; this file holds no secrets).
export KAFKA_ENV=cc
_target_env="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/target.env"
if [ -f "$_target_env" ]; then
  source "$_target_env"
else
  echo "target.env not found; run kcp/write_target_env.sh (STEP-2) first."
fi
unset _target_env
