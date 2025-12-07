# Section 00: Project Overview

## Goal

Understand the complete MLOps architecture, key components, and how they fit together in a production churn prediction system for an e-learning portal.

---

## The Business Problem

**TechITFactory** is an e-learning platform offering DevOps, Kubernetes, and Cloud courses. They face a common challenge:

- **Churn**: Users stop engaging with the platform (no logins, no video watches, no course activity)
- **Impact**: Lost revenue, wasted marketing spend, missed retention opportunities
- **Need**: Predict which users are likely to churn so the business can intervene (send offers, personalized outreach, etc.)

---

## MLOps System Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                         DATA LAYER                                │
├──────────────────────────────────────────────────────────────────┤
│  Raw Events (logins, video_watch, payments, etc.)                │
│         ↓                                                         │
│  Validation Gates → Processed Tables → Feature Engineering       │
└──────────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────────┐
│                       TRAINING LAYER                              │
├──────────────────────────────────────────────────────────────────┤
│  Labels (churn_label) ← Processed Data                           │
│         ↓                                                         │
│  Training Set (features + labels) → Train Models                 │
│         ↓                                                         │
│  Model Registry (versioned .joblib + metrics.json)               │
│         ↓                                                         │
│  Promotion Logic → production_latest.joblib                      │
└──────────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────────┐
│                      INFERENCE LAYER                              │
├──────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐           ┌──────────────────┐             │
│  │  Batch Scoring  │           │  Real-time API   │             │
│  │  (CronJob)      │           │  (FastAPI)       │             │
│  └─────────────────┘           └──────────────────┘             │
│           ↓                              ↓                        │
│  High-risk user list         Single user churn_risk             │
└──────────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────────┐
│                     MONITORING LAYER                              │
├──────────────────────────────────────────────────────────────────┤
│  - Data Drift Detection (PSI on features)                        │
│  - Model Performance Tracking (Prometheus metrics)               │
│  - Score Proxy (label actual outcomes for monitoring)            │
│  - Automated Retrain Trigger (when drift > threshold)            │
└──────────────────────────────────────────────────────────────────┘
```

---

## Key Components

### 1. Data Pipeline
- **Generate**: Synthetic data generator creates realistic user behavior
- **Validate**: Quality gates ensure data integrity before processing
- **Prepare**: Raw events → cleaned tables → user_daily aggregation
- **Features**: Rolling windows (7d, 14d, 30d) for engagement metrics

### 2. Training Pipeline
- **Labels**: Define churn as "zero activity in next 30 days"
- **Training Set**: Join features + labels, time-aware split
- **Model**: Logistic Regression (baseline), sklearn pipeline
- **Registry**: Timestamped artifacts + metrics, promotion to production alias

### 3. Inference Layer
- **Batch**: Daily/weekly scoring of all active users → CSV output
- **Real-time**: FastAPI endpoint for on-demand predictions
- **Score Proxy**: Collect actual outcomes to monitor model accuracy

### 4. Deployment
- **Docker**: Separate images for ML workloads (`churn-ml`) and API (`churn-api`)
- **Kubernetes**: Jobs for training, Deployments for API, CronJobs for scheduled tasks
- **Storage**: PersistentVolumeClaim for shared data and artifacts

### 5. Monitoring & Retraining
- **Drift Detection**: PSI (Population Stability Index) on feature distributions
- **Alerting**: Drift CronJob logs warnings when PSI exceeds thresholds
- **Retrain**: Weekly CronJob or manual trigger to refresh model

---

## Repository Structure Overview

```
churn-mlops-prod/
├── src/churn_mlops/              # Python package
│   ├── common/                   # Config, logging, utils
│   ├── data/                     # Data generation, validation, preparation
│   ├── features/                 # Feature engineering
│   ├── training/                 # Label creation, training, promotion
│   ├── inference/                # Batch scoring
│   ├── monitoring/               # Drift, metrics, score proxy
│   └── api/                      # FastAPI app
├── scripts/                      # Shell wrappers for each step
├── config/                       # YAML configuration
├── docker/                       # Dockerfile.ml, Dockerfile.api
├── k8s/                          # Kubernetes manifests
│   ├── plain/                    # Plain YAML (no Kustomize)
│   └── helm/                     # Helm chart (WIP)
├── data/                         # Data artifacts (raw, processed, features, predictions)
├── artifacts/                    # Model artifacts (models/, metrics/)
├── requirements/                 # Python dependencies (base, dev, api, serving)
└── tests/                        # Unit tests
```

---

## Data Flow Example

**Day 1: Generate & Train**
```bash
# Generate 2000 users, 120 days of events
python -m churn_mlops.data.generate_synthetic

# Validate raw data quality
python -m churn_mlops.data.validate

# Clean and create user_daily table
python -m churn_mlops.data.prepare_dataset

# Build rolling features (7d, 14d, 30d)
python -m churn_mlops.features.build_features

# Create churn labels (30d forward-looking)
python -m churn_mlops.training.build_labels

# Merge features + labels
python -m churn_mlops.training.build_training_set

# Train baseline model
python -m churn_mlops.training.train_baseline

# Promote best model to production_latest.joblib
python -m churn_mlops.training.promote_model
```

**Day 2: Score & Serve**
```bash
# Batch score all users
python -m churn_mlops.inference.batch_score

# Start API
uvicorn churn_mlops.api.app:app --host 0.0.0.0 --port 8000

# Predict for a single user
curl -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{"user_id": "1234", "features": {...}}'
```

**Day 3: Monitor**
```bash
# Check for data drift
python -m churn_mlops.monitoring.run_drift_check

# Collect actual outcomes (score proxy)
python -m churn_mlops.monitoring.run_score_proxy

# If drift detected → retrain
./scripts/train_candidate.sh
./scripts/promote_model.sh
kubectl -n churn-mlops rollout restart deployment/churn-api
```

---

## Execution Modes

### Local Python
- **Best for**: Development, debugging, feature exploration
- **Setup**: `python -m venv .venv && source .venv/bin/activate && make setup`
- **Run**: Individual scripts or `make all`

### Docker Compose (Not included, but easy to add)
- **Best for**: Testing containerized workflows locally
- **Run**: `docker-compose up` (would need docker-compose.yml)

### Kubernetes (Minikube)
- **Best for**: Production-like environment, learning K8s
- **Setup**: `minikube start && kubectl apply -f k8s/`
- **Run**: Jobs for training, Deployment for API, CronJobs for automation

---

## Key Decisions & Trade-offs

| Decision | Rationale | Trade-off |
|----------|-----------|-----------|
| **Logistic Regression** | Fast, interpretable, good baseline | Lower ceiling than deep learning |
| **CSV files** | Easy to inspect, version control friendly | Not efficient for TB-scale |
| **Time-based split** | Respects temporal nature of churn | Slightly more complex than random split |
| **30-day churn window** | Balances signal vs. data freshness | Could tune to 14d or 60d |
| **Separate ML & API images** | ML image has scripts, API image is lean | Two images to maintain |
| **PVC for K8s storage** | Shared state across pods | Single point of failure (mitigated in prod) |
| **Python modules, not notebooks** | Production-ready, testable, CI/CD friendly | Less interactive for exploration |

---

## Success Metrics

**Data Quality**
- ✅ Validation passes: no schema violations, referential integrity maintained
- ✅ User_daily coverage: 100% of users have daily records

**Model Performance**
- ✅ PR-AUC > 0.60 (better than random for imbalanced data)
- ✅ ROC-AUC > 0.70
- ✅ Precision@K (top 50 high-risk users) > 40%

**System Reliability**
- ✅ API uptime > 99.5%
- ✅ Batch scoring completes in < 5 minutes
- ✅ Drift checks run daily without failure

**Developer Experience**
- ✅ `make all` runs end-to-end without errors
- ✅ `kubectl apply -f k8s/` deploys successfully
- ✅ All tests pass (`pytest`)

---

## Learning Outcomes

By the end of this course, you will:

1. **Understand** the full MLOps lifecycle (data → train → deploy → monitor → retrain)
2. **Build** a production-grade churn prediction system from scratch
3. **Deploy** ML models using Docker and Kubernetes
4. **Monitor** model drift and automate retraining
5. **Write** clean, testable Python code for ML systems
6. **Troubleshoot** common issues in ML deployment

---

## Next Steps

- **[Section 01](section-01-understanding-churn.md)**: Deep dive into the churn problem
- **[file-index.md](file-index.md)**: Complete file reference
- **[Section 02](section-02-repo-blueprint-env.md)**: Project structure and environment setup

---

## References

- **Course Repository**: https://github.com/Dhananjaiah/churn-mlops-prod
- **MLOps Best Practices**: Google's "Practitioners Guide to MLOps" (https://cloud.google.com/architecture/mlops-continuous-delivery-and-automation-pipelines-in-machine-learning)
- **Churn Prediction**: Commonly used in SaaS, e-learning, telco, finance
