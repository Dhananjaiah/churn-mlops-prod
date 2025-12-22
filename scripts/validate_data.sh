#!/usr/bin/env bash
set -euo pipefail

# Resolve repo root (works even if script is run from another directory)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Activate venv if present (from repo root)
if [ -f "${REPO_ROOT}/.venv/bin/activate" ]; then
  # shellcheck disable=SC1090
  source "${REPO_ROOT}/.venv/bin/activate"
fi

LOCAL_RAW="${REPO_ROOT}/data/raw"
CONTAINER_RAW="/app/data/raw"

need_files_exist() {
  local dir="$1"
  [ -f "${dir}/users.csv" ] && [ -f "${dir}/events.csv" ]
}

# If user explicitly set CHURN_MLOPS_CONFIG and it exists, trust it
if [ "${CHURN_MLOPS_CONFIG:-}" != "" ] && [ -f "${CHURN_MLOPS_CONFIG}" ]; then
  echo "Using CHURN_MLOPS_CONFIG=${CHURN_MLOPS_CONFIG}"
  python -m churn_mlops.data.validate
  exit 0
fi

TMP_CFG=""
cleanup() { [ -n "${TMP_CFG}" ] && rm -f "${TMP_CFG}"; }
trap cleanup EXIT

# 1) Prefer container path if files exist there (Docker / mounted volumes)
if need_files_exist "${CONTAINER_RAW}"; then
  if [ -f "/app/config/config.yaml" ]; then
    export CHURN_MLOPS_CONFIG="/app/config/config.yaml"
    echo "Detected container data at ${CONTAINER_RAW}. Using ${CHURN_MLOPS_CONFIG}"
  else
    # Fallback: generate a minimal config pointing at /app paths
    TMP_CFG="$(mktemp)"
    cat > "${TMP_CFG}" <<YAML
paths:
  data: /app/data
  raw: /app/data/raw
  processed: /app/data/processed
  features: /app/data/features
  predictions: /app/data/predictions
  artifacts: /app/artifacts
  models: /app/artifacts/models
  metrics: /app/artifacts/metrics
YAML
    export CHURN_MLOPS_CONFIG="${TMP_CFG}"
    echo "Detected container data at ${CONTAINER_RAW}. Using generated config ${CHURN_MLOPS_CONFIG}"
  fi

# 2) Otherwise use local repo path if files exist there
elif need_files_exist "${LOCAL_RAW}"; then
  if [ -f "${REPO_ROOT}/configs/config.yaml" ]; then
    export CHURN_MLOPS_CONFIG="${REPO_ROOT}/configs/config.yaml"
    echo "Detected local data at ${LOCAL_RAW}. Using ${CHURN_MLOPS_CONFIG}"
  else
    # Generate a minimal local config (doesn't touch existing Docker config)
    TMP_CFG="$(mktemp)"
    cat > "${TMP_CFG}" <<YAML
paths:
  data: ${REPO_ROOT}/data
  raw: ${REPO_ROOT}/data/raw
  processed: ${REPO_ROOT}/data/processed
  features: ${REPO_ROOT}/data/features
  predictions: ${REPO_ROOT}/data/predictions
  artifacts: ${REPO_ROOT}/artifacts
  models: ${REPO_ROOT}/artifacts/models
  metrics: ${REPO_ROOT}/artifacts/metrics
YAML
    export CHURN_MLOPS_CONFIG="${TMP_CFG}"
    echo "Detected local data at ${LOCAL_RAW}. Using generated config ${CHURN_MLOPS_CONFIG}"
  fi

else
  echo "RAW DATA VALIDATION FAILED ❌"
  echo "Could not find required files in either location:"
  echo " - ${CONTAINER_RAW}/users.csv and ${CONTAINER_RAW}/events.csv"
  echo " - ${LOCAL_RAW}/users.csv and ${LOCAL_RAW}/events.csv"
  echo ""
  echo "Tip: run ./scripts/generate_data.sh first, then retry."
  exit 1
fi

python -m churn_mlops.data.validate
