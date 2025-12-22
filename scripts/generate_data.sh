#!/usr/bin/env bash
set -euo pipefail

# Resolve repo root (works even if run from another directory)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Activate venv if present
if [ -f "${REPO_ROOT}/.venv/bin/activate" ]; then
  # shellcheck disable=SC1090
  source "${REPO_ROOT}/.venv/bin/activate"
fi

LOCAL_OUT="${REPO_ROOT}/data/raw"
CONTAINER_OUT="/app/data/raw"

mkdir -p "${REPO_ROOT}/data/raw" "${REPO_ROOT}/data/processed" "${REPO_ROOT}/data/features" "${REPO_ROOT}/data/predictions" || true

# If we're inside a container-like layout and /app/data exists, use it
if [ -d "/app" ] && ( [ -d "/app/data" ] || [ -w "/app" ] ); then
  OUT_DIR="${CONTAINER_OUT}"
else
  OUT_DIR="${LOCAL_OUT}"
fi

echo "Generating synthetic data into: ${OUT_DIR}"

python -m churn_mlops.data.generate_synthetic \
  --output-dir "${OUT_DIR}" \
  --n-users 2000 \
  --days 120 \
  --start-date 2025-01-01 \
  --seed 42 \
  --paid-ratio 0.35 \
  --churn-base-rate 0.35
