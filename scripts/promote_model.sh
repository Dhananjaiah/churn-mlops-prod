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
LOCAL_REGISTRY="${REPO_ROOT}/artifacts/registry"
CONTAINER_ARTIFACTS="/app/artifacts"
CONTAINER_MODELS="/app/artifacts/models"
CONTAINER_REGISTRY="/app/artifacts/registry"

dir_nonempty() {
  local d="$1"
  [ -d "$d" ] && [ "$(ls -A "$d" 2>/dev/null | wc -l)" -gt 0 ]
}

dir_writable() {
  local d="$1"
  mkdir -p "$d" 2>/dev/null && [ -w "$d" ]
}

# If user explicitly set CHURN_MLOPS_CONFIG and it exists, trust it
if [ "${CHURN_MLOPS_CONFIG:-}" != "" ] && [ -f "${CHURN_MLOPS_CONFIG}" ]; then
  echo "Using CHURN_MLOPS_CONFIG=${CHURN_MLOPS_CONFIG}"
  python -m churn_mlops.training.promote_model
  exit 0
fi

TMP_CFG=""
cleanup() { [ -n "${TMP_CFG}" ] && rm -f "${TMP_CFG}"; }
trap cleanup EXIT

# Prefer container if it looks like we have models there and can write registry
if dir_nonempty "${CONTAINER_MODELS}" && dir_writable "${CONTAINER_REGISTRY}"; then
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
    echo "Detected container artifacts. Using generated config ${CHURN_MLOPS_CONFIG}"
  fi

# Otherwise use local if we have models and can write registry
elif dir_nonempty "${LOCAL_MODELS}" && dir_writable "${LOCAL_REGISTRY}"; then
  mkdir -p "${LOCAL_ARTIFACTS}/metrics" || true
  if [ -f "${REPO_ROOT}/configs/config.yaml" ]; then
    export CHURN_MLOPS_CONFIG="${REPO_ROOT}/configs/config.yaml"
    echo "Detected local artifacts at ${LOCAL_ARTIFACTS}. Using ${CHURN_MLOPS_CONFIG}"
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
    echo "Detected local artifacts. Using generated config ${CHURN_MLOPS_CONFIG}"
  fi

else
  echo "PROMOTE MODEL FAILED ❌"
  echo "Need a trained model in artifacts/models and a writable artifacts/registry."
  echo ""
  echo "Checked container:"
  echo " - models:   ${CONTAINER_MODELS}"
  echo " - registry: ${CONTAINER_REGISTRY}"
  echo ""
  echo "Checked local:"
  echo " - models:   ${LOCAL_MODELS}"
  echo " - registry: ${LOCAL_REGISTRY}"
  echo ""
  echo "Tip: run training first (baseline/candidate), then retry."
  exit 1
fi

python -m churn_mlops.training.promote_model
