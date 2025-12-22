#!/usr/bin/env bash
set -euo pipefail

# Resolve repo root (works even if run from another directory)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Activate venv if present
if [ -f "${REPO_ROOT}/.venv/bin/activate" ]; then
  # shellcheck disable=SC1090
  source "${REPO_ROOT}/.venv/bin/activate"
fi

LOCAL_RAW="${REPO_ROOT}/data/raw"
LOCAL_PROCESSED="${REPO_ROOT}/data/processed"
CONTAINER_RAW="/app/data/raw"
CONTAINER_PROCESSED="/app/data/processed"

need_files_exist() {
  local dir="$1"
  [ -f "${dir}/users.csv" ] && [ -f "${dir}/events.csv" ]
}

# If user explicitly set CHURN_MLOPS_CONFIG and it exists, trust it
if [ "${CHURN_MLOPS_CONFIG:-}" != "" ] && [ -f "${CHURN_MLOPS_CONFIG}" ]; then
  echo "Using CHURN_MLOPS_CONFIG=${CHURN_MLOPS_CONFIG}"
  python -m churn_mlops.data.prepare_dataset
  exit 0
fi

TMP_CFG=""
cleanup() { [ -n "${TMP_CFG}" ] && rm -f "${TMP_CFG}"; }
trap cleanup EXIT

# Prefer container path if raw files exist there
if need_files_exist "${CONTAINER_RAW}"; then
  if [ -f "/app/config/config.yaml" ]; then
    export CHURN_MLOPS_CONFIG="/app/config/config.yaml"
    echo "Detected container raw data at ${CONTAINER_RAW}. Using ${CHURN_MLOPS_CONFIG}"
  else
    TMP_CFG="$(mktemp)"
    cat > "${TMP_CFG}" <<YAML
paths:
  raw: /app/data/raw
  processed: /app/data/processed
  features: /app/data/features
  predictions: /app/data/predictions
  artifacts: /app/artifacts
  models: /app/artifacts/models
  metrics: /app/artifacts/metrics
YAML
    export CHURN_MLOPS_CONFIG="${TMP_CFG}"
    echo "Detected container raw data at ${CONTAINER_RAW}. Using generated config ${CHURN_MLOPS_CONFIG}"
  fi

# Otherwise use local repo path if raw files exist there
elif need_files_exist "${LOCAL_RAW}"; then
  mkdir -p "${LOCAL_PROCESSED}" || true
  if [ -f "${REPO_ROOT}/configs/config.yaml" ]; then
    export CHURN_MLOPS_CONFIG="${REPO_ROOT}/configs/config.yaml"
    echo "Detected local raw data at ${LOCAL_RAW}. Using ${CHURN_MLOPS_CONFIG}"
  else
    TMP_CFG="$(mktemp)"
    cat > "${TMP_CFG}" <<YAML
paths:
  raw: ${LOCAL_RAW}
  processed: ${LOCAL_PROCESSED}
  features: ${REPO_ROOT}/data/features
  predictions: ${REPO_ROOT}/data/predictions
  artifacts: ${REPO_ROOT}/artifacts
  models: ${REPO_ROOT}/artifacts/models
  metrics: ${REPO_ROOT}/artifacts/metrics
YAML
    export CHURN_MLOPS_CONFIG="${TMP_CFG}"
    echo "Detected local raw data at ${LOCAL_RAW}. Using generated config ${CHURN_MLOPS_CONFIG}"
  fi

else
  echo "PREPARE DATA FAILED ❌"
  echo "Could not find required raw files in either location:"
  echo " - ${CONTAINER_RAW}/users.csv and ${CONTAINER_RAW}/events.csv"
  echo " - ${LOCAL_RAW}/users.csv and ${LOCAL_RAW}/events.csv"
  echo ""
  echo "Tip: run ./scripts/generate_data.sh first, then retry."
  exit 1
fi

python -m churn_mlops.data.prepare_dataset
