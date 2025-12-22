#!/usr/bin/env bash
set -euo pipefail

# Resolve repo root (works even if run from another directory)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Activate venv if present
if [ -f "${REPO_ROOT}/.venv/bin/activate" ]; then
  # shellcheck disable=SC1090
  source "${REPO_ROOT}/.venv/bin/activate"
fi

LOCAL_ARTIFACTS="${REPO_ROOT}/artifacts"
LOCAL_MODELS="${REPO_ROOT}/artifacts/models"
CONTAINER_ARTIFACTS="/app/artifacts"
CONTAINER_MODELS="/app/artifacts/models"

# We'll consider artifacts dir "ready" if it's writable (training needs to write)
dir_writable() {
  local d="$1"
  mkdir -p "$d" 2>/dev/null && [ -w "$d" ]
}

# If user explicitly set CHURN_MLOPS_CONFIG and it exists, trust it
if [ "${CHURN_MLOPS_CONFIG:-}" != "" ] && [ -f "${CHURN_MLOPS_CONFIG}" ]; then
  echo "Using CHURN_MLOPS_CONFIG=${CHURN_MLOPS_CONFIG}"
  python -m churn_mlops.training.train_baseline
  exit 0
fi

TMP_CFG=""
cleanup() { [ -n "${TMP_CFG}" ] && rm -f "${TMP_CFG}"; }
trap cleanup EXIT

# Prefer container if artifacts path exists and is writable
if dir_writable "${CONTAINER_MODELS}"; then
  if [ -f "/app/config/config.yaml" ]; then
    export CHURN_MLOPS_CONFIG="/app/config/config.yaml"
    echo "Detected container artifacts at ${CONTAINER_ARTIFACTS}. Using ${CHURN_MLOPS_CONFIG}"
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
    echo "Detected container artifacts at ${CONTAINER_ARTIFACTS}. Using generated config ${CHURN_MLOPS_CONFIG}"
  fi

# Otherwise use local
elif dir_writable "${LOCAL_MODELS}"; then
  if [ -f "${REPO_ROOT}/configs/config.yaml" ]; then
    export CHURN_MLOPS_CONFIG="${REPO_ROOT}/configs/config.yaml"
    echo "Using ${CHURN_MLOPS_CONFIG}"
  else
    TMP_CFG="$(mktemp)"
    cat > "${TMP_CFG}" <<YAML
paths:
  raw: ${REPO_ROOT}/data/raw
  processed: ${REPO_ROOT}/data/processed
  features: ${REPO_ROOT}/data/features
  predictions: ${REPO_ROOT}/data/predictions
  artifacts: ${REPO_ROOT}/artifacts
  models: ${REPO_ROOT}/artifacts/models
  metrics: ${REPO_ROOT}/artifacts/metrics
YAML
    export CHURN_MLOPS_CONFIG="${TMP_CFG}"
    echo "Using generated config ${CHURN_MLOPS_CONFIG}"
  fi

else
  echo "TRAIN BASELINE FAILED ❌"
  echo "Could not find a writable artifacts/models directory in either location:"
  echo " - ${CONTAINER_MODELS}"
  echo " - ${LOCAL_MODELS}"
  echo ""
  echo "Tip: ensure artifacts folder exists and is writable."
  exit 1
fi

python -m churn_mlops.training.train_baseline
