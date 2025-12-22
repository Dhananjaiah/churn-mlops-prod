#!/usr/bin/env bash
set -euo pipefail

# Resolve repo root (works even if run from another directory)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Activate venv if present
if [ -f "${REPO_ROOT}/.venv/bin/activate" ]; then
  # shellcheck disable=SC1090
  source "${REPO_ROOT}/.venv/bin/activate"
fi

LOCAL_FEATURES="${REPO_ROOT}/data/features"
LOCAL_PROCESSED="${REPO_ROOT}/data/processed"
CONTAINER_FEATURES="/app/data/features"
CONTAINER_PROCESSED="/app/data/processed"

need_inputs_exist() {
  local features_dir="$1"
  local processed_dir="$2"
  [ -d "${features_dir}" ] && [ "$(ls -A "${features_dir}" 2>/dev/null | wc -l)" -gt 0 ] && \
  [ -d "${processed_dir}" ] && [ "$(ls -A "${processed_dir}" 2>/dev/null | wc -l)" -gt 0 ]
}

# If user explicitly set CHURN_MLOPS_CONFIG and it exists, trust it
if [ "${CHURN_MLOPS_CONFIG:-}" != "" ] && [ -f "${CHURN_MLOPS_CONFIG}" ]; then
  echo "Using CHURN_MLOPS_CONFIG=${CHURN_MLOPS_CONFIG}"
  python -m churn_mlops.training.build_training_set
  exit 0
fi

TMP_CFG=""
cleanup() { [ -n "${TMP_CFG}" ] && rm -f "${TMP_CFG}"; }
trap cleanup EXIT

# Prefer container if inputs exist there
if need_inputs_exist "${CONTAINER_FEATURES}" "${CONTAINER_PROCESSED}"; then
  if [ -f "/app/config/config.yaml" ]; then
    export CHURN_MLOPS_CONFIG="/app/config/config.yaml"
    echo "Detected container inputs. Using ${CHURN_MLOPS_CONFIG}"
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
    echo "Detected container inputs. Using generated config ${CHURN_MLOPS_CONFIG}"
  fi

# Otherwise use local
elif need_inputs_exist "${LOCAL_FEATURES}" "${LOCAL_PROCESSED}"; then
  if [ -f "${REPO_ROOT}/configs/config.yaml" ]; then
    export CHURN_MLOPS_CONFIG="${REPO_ROOT}/configs/config.yaml"
    echo "Detected local inputs. Using ${CHURN_MLOPS_CONFIG}"
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
    echo "Detected local inputs. Using generated config ${CHURN_MLOPS_CONFIG}"
  fi

else
  echo "BUILD TRAINING SET FAILED ❌"
  echo "Could not find required inputs in either location:"
  echo " - Features:   ${CONTAINER_FEATURES} or ${LOCAL_FEATURES}"
  echo " - Processed:  ${CONTAINER_PROCESSED} or ${LOCAL_PROCESSED}"
  echo ""
  echo "Tip: run these first:"
  echo "  ./scripts/prepare_data.sh"
  echo "  ./scripts/build_features.sh"
  echo "  ./scripts/build_labels.sh"
  exit 1
fi

python -m churn_mlops.training.build_training_set
