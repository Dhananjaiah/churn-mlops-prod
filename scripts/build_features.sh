#!/usr/bin/env bash
set -euo pipefail

# Resolve repo root (works even if run from another directory)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Activate venv if present
if [ -f "${REPO_ROOT}/.venv/bin/activate" ]; then
  # shellcheck disable=SC1090
  source "${REPO_ROOT}/.venv/bin/activate"
fi

LOCAL_PROCESSED="${REPO_ROOT}/data/processed"
CONTAINER_PROCESSED="/app/data/processed"

need_processed_exist() {
  local dir="$1"
  # Keep this lenient: many pipelines just need "something" in processed
  [ -d "${dir}" ] && [ "$(ls -A "${dir}" 2>/dev/null | wc -l)" -gt 0 ]
}

# If user explicitly set CHURN_MLOPS_CONFIG and it exists, trust it
if [ "${CHURN_MLOPS_CONFIG:-}" != "" ] && [ -f "${CHURN_MLOPS_CONFIG}" ]; then
  echo "Using CHURN_MLOPS_CONFIG=${CHURN_MLOPS_CONFIG}"
  python -m churn_mlops.features.build_features
  exit 0
fi

TMP_CFG=""
cleanup() { [ -n "${TMP_CFG}" ] && rm -f "${TMP_CFG}"; }
trap cleanup EXIT

# Prefer container if processed exists there
if need_processed_exist "${CONTAINER_PROCESSED}"; then
  if [ -f "/app/config/config.yaml" ]; then
    export CHURN_MLOPS_CONFIG="/app/config/config.yaml"
    echo "Detected container processed data at ${CONTAINER_PROCESSED}. Using ${CHURN_MLOPS_CONFIG}"
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
    echo "Detected container processed data at ${CONTAINER_PROCESSED}. Using generated config ${CHURN_MLOPS_CONFIG}"
  fi

# Otherwise use local
elif need_processed_exist "${LOCAL_PROCESSED}"; then
  if [ -f "${REPO_ROOT}/configs/config.yaml" ]; then
    export CHURN_MLOPS_CONFIG="${REPO_ROOT}/configs/config.yaml"
    echo "Detected local processed data at ${LOCAL_PROCESSED}. Using ${CHURN_MLOPS_CONFIG}"
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
    echo "Detected local processed data at ${LOCAL_PROCESSED}. Using generated config ${CHURN_MLOPS_CONFIG}"
  fi

else
  echo "BUILD FEATURES FAILED ❌"
  echo "Could not find any processed data in either location:"
  echo " - ${CONTAINER_PROCESSED}"
  echo " - ${LOCAL_PROCESSED}"
  echo ""
  echo "Tip: run ./scripts/prepare_data.sh first, then retry."
  exit 1
fi

python -m churn_mlops.features.build_features
