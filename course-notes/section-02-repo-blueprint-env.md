# Section 02: Repository Blueprint & Environment

## Goal

Understand the project structure, configuration system, dependency management, and how to set up a development environment.

---

## Repository Structure

```
churn-mlops-prod/
├── src/churn_mlops/              # Main Python package
│   ├── __init__.py               # Package marker (empty)
│   ├── common/                   # Shared utilities
│   │   ├── config.py             # YAML config loader with env var support
│   │   ├── paths.py              # Project root path helper
│   │   ├── logging.py            # Centralized logging setup
│   │   └── utils.py              # Utility functions (ensure_dir)
│   ├── data/                     # Data pipeline modules
│   │   ├── generate_synthetic.py # Synthetic data generation
│   │   ├── validate.py           # Data quality validation gates
│   │   └── prepare_dataset.py    # Data cleaning & aggregation
│   ├── features/                 # Feature engineering
│   │   └── build_features.py     # Rolling windows, engagement features
│   ├── training/                 # Model training pipeline
│   │   ├── build_labels.py       # Churn label creation
│   │   ├── build_training_set.py # Feature + label merge
│   │   ├── train_baseline.py     # Baseline model (Logistic Regression)
│   │   ├── train_candidate.py    # Candidate model (same, for retraining)
│   │   └── promote_model.py      # Model promotion logic
│   ├── inference/                # Prediction pipeline
│   │   └── batch_score.py        # Batch scoring for all users
│   ├── monitoring/               # Observability & drift
│   │   ├── api_metrics.py        # Prometheus metrics for API
│   │   ├── drift.py              # PSI drift calculation
│   │   ├── run_drift_check.py    # Drift detection runner
│   │   ├── score_proxy.py        # Actual outcome collection
│   │   └── run_score_proxy.py    # Score proxy runner
│   └── api/                      # FastAPI application
│       └── app.py                # Real-time prediction API
├── scripts/                      # Shell script wrappers
│   ├── generate_data.sh          # Generate synthetic data
│   ├── validate_data.sh          # Run validation
│   ├── prepare_data.sh           # Prepare datasets
│   ├── build_features.sh         # Build features
│   ├── build_labels.sh           # Build labels
│   ├── build_training_set.sh     # Build training set
│   ├── train_baseline.sh         # Train baseline model
│   ├── train_candidate.sh        # Train candidate model
│   ├── promote_model.sh          # Promote best model
│   ├── batch_score.sh            # Run batch scoring
│   ├── batch_score_latest.sh     # Score latest date
│   ├── ensure_latest_predictions.sh  # Ensure predictions exist
│   ├── score_proxy.sh            # Run score proxy
│   ├── run_batch_score_and_proxy.sh  # Combined batch + proxy
│   ├── check_drift.sh            # Run drift check
│   ├── monitor_data_drift.sh     # Monitor drift
│   ├── run_api.sh                # Start API locally
│   └── bootstrap_minikube.sh     # Setup minikube cluster
├── config/                       # Configuration (single file, legacy)
│   └── config.yaml               # Main config (container paths)
├── configs/                      # Multi-environment configs
│   ├── config.yaml               # Default (points to container paths)
│   ├── config.dev.yaml           # Development overrides
│   ├── config.stage.yaml         # Staging overrides
│   └── config.prod.yaml          # Production overrides
├── docker/                       # Docker images
│   ├── Dockerfile.ml             # ML workload image (includes scripts)
│   └── Dockerfile.api            # API image (lean, uvicorn)
├── k8s/                          # Kubernetes manifests
│   ├── namespace.yaml            # churn-mlops namespace
│   ├── pvc.yaml                  # Shared storage (5Gi)
│   ├── configmap.yaml            # Config file as ConfigMap
│   ├── seed-model-job.yaml       # Initial training job
│   ├── api-deployment.yaml       # API deployment (2 replicas)
│   ├── api-service.yaml          # API service (ClusterIP)
│   ├── batch-cronjob.yaml        # Daily batch scoring
│   ├── batch-score-proxy-cronjob.yaml  # Combined batch+proxy
│   ├── drift-cronjob.yaml        # Daily drift check
│   ├── retrain-cronjob.yaml      # Weekly retrain
│   ├── ml-scripts-configmap.yaml # Scripts as ConfigMap (alternative)
│   ├── api-metrics-annotations-patch.yaml  # Prometheus scrape config
│   ├── plain/                    # Plain YAML (validated approach)
│   │   ├── namespace.yaml
│   │   ├── pvc.yaml
│   │   ├── configmap.yaml
│   │   ├── seed-model-job.yaml
│   │   ├── api-deployment.yaml
│   │   ├── api-service.yaml
│   │   └── batch-score-proxy-cronjob.yaml
│   ├── monitoring/               # Observability
│   │   └── servicemonitor.yaml   # Prometheus ServiceMonitor
│   └── helm/                     # Helm chart (WIP)
│       └── churn-mlops/          # Chart directory
│           ├── Chart.yaml
│           ├── values.yaml
│           └── templates/
├── data/                         # Data storage (local/PVC)
│   ├── raw/                      # users.csv, events.csv
│   ├── processed/                # users_clean.csv, events_clean.csv, user_daily.csv, labels_daily.csv
│   ├── features/                 # user_features_daily.csv, training_dataset.csv
│   └── predictions/              # churn_predictions_<date>.csv
├── artifacts/                    # Model artifacts
│   ├── models/                   # baseline_logreg_<timestamp>.joblib, production_latest.joblib
│   └── metrics/                  # baseline_logreg_<timestamp>.json, production_latest.json
├── requirements/                 # Python dependencies
│   ├── base.txt                  # Core ML deps (pandas, sklearn, numpy)
│   ├── runtime.txt               # Alias for base.txt
│   ├── api.txt                   # API deps (fastapi, uvicorn, prometheus_client)
│   ├── serving.txt               # Serving deps (same as api.txt + joblib)
│   └── dev.txt                   # Dev tools (pytest, ruff, black)
├── tests/                        # Unit tests
│   └── test_*.py                 # Test modules
├── pyproject.toml                # Python project metadata
├── ruff.toml                     # Ruff linter config
├── Makefile                      # Common tasks (lint, test, train, etc.)
├── docker-compose.yml            # Docker Compose config (simple setup)
├── README.md                     # Main project README
└── .gitignore                    # Git ignore patterns
```

---

## Configuration System

### File: `src/churn_mlops/common/config.py`

**Features**:
- YAML-based configuration
- Environment variable support (`CHURN_MLOPS_CONFIG`)
- Deep merge for config overrides
- Fallback defaults

**Usage**:
```python
from churn_mlops.common.config import load_config

cfg = load_config()
# Reads from:
# 1. $CHURN_MLOPS_CONFIG env var (if set)
# 2. config/config.yaml (default)
# 3. Built-in defaults

print(cfg["paths"]["models"])  # /app/artifacts/models
```

### Config Structure

**File**: `config/config.yaml`
```yaml
app:
  name: churn-mlops
  env: dev
  log_level: INFO

paths:
  data: /app/data
  raw: /app/data/raw
  processed: /app/data/processed
  features: /app/data/features
  predictions: /app/data/predictions
  artifacts: /app/artifacts
  models: /app/artifacts/models
  metrics: /app/artifacts/metrics

features:
  windows_days: [7, 14, 30]

churn:
  window_days: 30
```

**Why `/app` paths?**
- Container-friendly (matches Docker WORKDIR)
- K8s PVC mount points (subPath: data, artifacts)
- Consistent across environments

---

## Dependency Management

### Base Dependencies (`requirements/base.txt`)
```
numpy>=1.24.0,<2.0
pandas>=2.0.0,<3.0
scikit-learn>=1.3.0,<2.0
joblib>=1.3.0
pyyaml>=6.0
python-dotenv>=1.0.0
```

**Purpose**: Core ML, data processing, config

### API Dependencies (`requirements/api.txt`)
```
fastapi>=0.104.0
uvicorn[standard]>=0.24.0
prometheus-client>=0.19.0
pydantic>=2.0.0
```

**Purpose**: Web framework, ASGI server, metrics

### Dev Dependencies (`requirements/dev.txt`)
```
pytest>=7.4.0
pytest-cov>=4.1.0
ruff>=0.1.0
black>=23.0.0
```

**Purpose**: Testing, linting, formatting

### Serving Dependencies (`requirements/serving.txt`)
```
# Same as api.txt plus joblib for model loading
-r api.txt
joblib>=1.3.0
```

---

## Environment Setup

### Local Python (Recommended for Development)

```bash
# 1. Clone repository
git clone https://github.com/Dhananjaiah/churn-mlops-prod.git
cd churn-mlops-prod

# 2. Create virtual environment
python -m venv .venv
source .venv/bin/activate  # Linux/Mac
# .venv\Scripts\activate   # Windows

# 3. Upgrade pip
pip install --upgrade pip

# 4. Install dependencies
pip install -r requirements/base.txt
pip install -r requirements/dev.txt
pip install -r requirements/api.txt

# 5. Install package in editable mode
pip install -e .

# 6. Verify installation
python -c "from churn_mlops.common.config import load_config; print('OK')"
```

### Using Makefile (Convenience)

```bash
# Install all dependencies
make setup

# Lint code
make lint

# Auto-fix imports
make lint-fix

# Format code
make format

# Run tests
make test

# Full pipeline
make all
```

---

## Logging Setup

### File: `src/churn_mlops/common/logging.py`

**Features**:
- Centralized logging configuration
- Log level from config (`app.log_level`)
- Structured format: `timestamp | level | logger | message`
- stdout output (container-friendly)

**Usage**:
```python
from churn_mlops.common.config import load_config
from churn_mlops.common.logging import setup_logging

cfg = load_config()
logger = setup_logging(cfg)

logger.info("Starting data generation")
logger.error("Validation failed: %s", error_msg)
```

**Output**:
```
2025-01-01 10:30:15 | INFO | churn-mlops | Starting data generation
2025-01-01 10:30:20 | ERROR | churn-mlops | Validation failed: missing column user_id
```

---

## Path Helpers

### File: `src/churn_mlops/common/paths.py`

```python
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[3]  # Go up to repo root

def rel(*parts: str) -> Path:
    return PROJECT_ROOT.joinpath(*parts)
```

**Usage**:
```python
from churn_mlops.common.paths import rel

data_dir = rel("data", "raw")  # /path/to/repo/data/raw
```

---

## Utility Functions

### File: `src/churn_mlops/common/utils.py`

```python
def ensure_dir(path: Union[str, Path]) -> Path:
    """Create directory if it doesn't exist."""
    p = Path(path)
    p.mkdir(parents=True, exist_ok=True)
    return p
```

**Usage**:
```python
from churn_mlops.common.utils import ensure_dir

models_dir = ensure_dir("artifacts/models")  # Creates if missing
```

---

## Python Package Structure

### File: `pyproject.toml`

```toml
[build-system]
requires = ["setuptools>=68", "wheel"]
build-backend = "setuptools.build_meta"

[project]
name = "techitfactory-churn-mlops"
version = "0.1.0"
description = "Production-grade churn prediction MLOps project."
requires-python = ">=3.10"

[tool.setuptools]
package-dir = {"" = "src"}

[tool.setuptools.packages.find]
where = ["src"]
```

**Why `src/` layout?**
- Enforces editable install (`pip install -e .`)
- Avoids accidental imports from CWD
- Standard for modern Python projects

---

## Linting & Formatting

### Ruff Configuration (`ruff.toml`)

```toml
line-length = 100
select = ["E", "F", "I", "B", "UP"]
ignore = ["E501"]
```

**Rules**:
- E: PEP 8 errors
- F: Pyflakes (unused imports, undefined names)
- I: isort (import sorting)
- B: flake8-bugbear (common bugs)
- UP: pyupgrade (modern Python syntax)

**Run**:
```bash
ruff check .                # Check for issues
ruff check . --fix          # Auto-fix
```

### Black (Code Formatter)

```bash
black .                     # Format all files
black --check .             # Check without modifying
```

---

## Testing

### File: `tests/test_*.py`

**Example**:
```python
# tests/test_config.py
from churn_mlops.common.config import load_config

def test_load_config():
    cfg = load_config()
    assert "app" in cfg
    assert "paths" in cfg
    assert cfg["app"]["name"] == "churn-mlops"
```

**Run**:
```bash
pytest                      # Run all tests
pytest -v                   # Verbose
pytest tests/test_config.py # Single file
```

---

## Docker Images

### ML Image (`docker/Dockerfile.ml`)

**Purpose**: Runs training, batch scoring, drift checks

**Key Features**:
- Includes `scripts/` directory (shell wrappers)
- Base + dev + serving dependencies
- WORKDIR `/app`
- CMD `bash` (generic entry point)

**Build**:
```bash
docker build -t techitfactory/churn-ml:0.1.0 -f docker/Dockerfile.ml .
```

### API Image (`docker/Dockerfile.api`)

**Purpose**: Runs FastAPI prediction service

**Key Features**:
- API dependencies only (lean image)
- CMD `uvicorn churn_mlops.api.app:app --host 0.0.0.0 --port 8000`
- EXPOSE 8000

**Build**:
```bash
docker build -t techitfactory/churn-api:0.1.0 -f docker/Dockerfile.api .
```

---

## Environment Variables

| Variable | Purpose | Example |
|----------|---------|---------|
| `CHURN_MLOPS_CONFIG` | Config file path | `/app/config/config.yaml` |
| `PYTHONPATH` | Python module search path | `/app/src` (usually auto-set) |
| `LOG_LEVEL` | Override log level | `DEBUG`, `INFO`, `WARNING` |

**Set in Docker**:
```bash
docker run -e CHURN_MLOPS_CONFIG=/app/config/config.yaml techitfactory/churn-ml:0.1.0
```

**Set in Kubernetes**:
```yaml
env:
  - name: CHURN_MLOPS_CONFIG
    value: /app/config/config.yaml
```

---

## File Patterns & Conventions

### Naming
- **Scripts**: `snake_case.sh` (e.g., `build_features.sh`)
- **Python modules**: `snake_case.py` (e.g., `build_features.py`)
- **Classes**: `PascalCase` (e.g., `DriftReport`)
- **Functions**: `snake_case` (e.g., `load_config`)

### Module Entry Points
```python
def main():
    cfg = load_config()
    logger = setup_logging(cfg)
    # ... business logic

if __name__ == "__main__":
    main()
```

**Run**:
```bash
python -m churn_mlops.data.generate_synthetic  # Module syntax
python src/churn_mlops/data/generate_synthetic.py  # File syntax (not recommended)
```

---

## Verification Steps

```bash
# 1. Check Python version
python --version  # Should be 3.10+

# 2. Verify package install
python -c "import churn_mlops; print('OK')"

# 3. Test config loading
python -c "from churn_mlops.common.config import load_config; print(load_config())"

# 4. Run linter
make lint

# 5. Run tests
make test

# 6. Check directory structure
ls -la src/churn_mlops
ls -la scripts
ls -la config
```

---

## Troubleshooting

**Issue**: `ModuleNotFoundError: No module named 'churn_mlops'`
- **Cause**: Package not installed or wrong Python interpreter
- **Fix**: Run `pip install -e .` and ensure virtual environment is activated

**Issue**: `FileNotFoundError: config/config.yaml`
- **Cause**: Running from wrong directory
- **Fix**: `cd` to repository root before running commands

**Issue**: `ImportError: attempted relative import beyond top-level package`
- **Cause**: Running Python files directly instead of as modules
- **Fix**: Use `python -m churn_mlops.module` syntax

**Issue**: Ruff or Black not found
- **Cause**: Dev dependencies not installed
- **Fix**: `pip install -r requirements/dev.txt`

---

## Next Steps

- **[Section 03](section-03-data-design.md)**: Data generation and schema design
- **[Section 04](section-04-data-validation-gates.md)**: Data quality validation
- **[file-index.md](file-index.md)**: Complete file reference

---

## Files Involved

| File | Purpose |
|------|---------|
| `src/churn_mlops/common/config.py` | Config loading with env var support |
| `src/churn_mlops/common/logging.py` | Centralized logging setup |
| `src/churn_mlops/common/paths.py` | Project root path helper |
| `src/churn_mlops/common/utils.py` | Utility functions |
| `pyproject.toml` | Python package metadata |
| `ruff.toml` | Linter configuration |
| `Makefile` | Common development tasks |
| `config/config.yaml` | Main configuration file |
| `requirements/*.txt` | Dependency specifications |
| `docker/Dockerfile.ml` | ML workload image |
| `docker/Dockerfile.api` | API service image |
