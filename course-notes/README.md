# Production-Grade MLOps Course Notes

## Churn Prediction for an E-Learning Portal

Welcome to the comprehensive course notes for building a production-grade MLOps system from scratch. This course covers the complete lifecycle of an ML system: **DATA → TRAIN → DEPLOY → MONITOR → RETRAIN**.

---

## 🎯 What You'll Build

A real-world churn prediction system for **TechITFactory**, an e-learning portal, featuring:

- **Synthetic data generation** for realistic e-learning user behavior
- **Data validation gates** to ensure quality before training
- **Feature engineering pipeline** with rolling aggregations and temporal features
- **Model training & registry** with versioned artifacts and metrics tracking
- **Batch scoring pipeline** for identifying high-risk users
- **Real-time prediction API** with FastAPI and Prometheus metrics
- **Docker containers** for reproducible ML and API workloads
- **Kubernetes deployment** with Jobs, CronJobs, and Services
- **Monitoring & drift detection** to track model and data quality
- **Automated retraining** triggered by drift or schedule

---

## 📚 Course Structure

| Section | Topic | Key Files |
|---------|-------|-----------|
| [00](section-00-overview.md) | **Overview** | Architecture & lifecycle |
| [01](section-01-understanding-churn.md) | **Understanding Churn** | Business problem definition |
| [02](section-02-repo-blueprint-env.md) | **Repo Blueprint & Environment** | Project structure, config, dependencies |
| [03](section-03-data-design.md) | **Data Design** | Synthetic generation, schema design |
| [04](section-04-data-validation-gates.md) | **Data Validation Gates** | Quality checks & validation logic |
| [05](section-05-feature-engineering.md) | **Feature Engineering** | Rolling features, temporal aggregations |
| [06](section-06-training-pipeline.md) | **Training Pipeline** | Label creation, train/test split, model training |
| [07](section-07-model-registry.md) | **Model Registry** | Versioning, promotion, production alias |
| [08](section-08-batch-scoring.md) | **Batch Scoring** | Bulk predictions for risk analysis |
| [09](section-09-realtime-api.md) | **Real-time API** | FastAPI service with health checks & metrics |
| [10](section-10-ci-cd-quality.md) | **CI/CD & Quality** | Linting, testing, code quality |
| [11](section-11-containerization-deploy.md) | **Containerization & Deploy** | Docker, Kubernetes manifests |
| [12](section-12-monitoring-retrain.md) | **Monitoring & Retrain** | Drift detection, automated retraining |
| [13](section-13-capstone-runbook.md) | **Capstone Runbook** | End-to-end workflows & troubleshooting |

---

## 🗂️ Reference Documents

- **[file-index.md](file-index.md)** - Complete file listing with descriptions
- **[Main README.md](../README.md)** - Repository overview and quick start

---

## 🚀 Quick Start Paths

### Local Development
```bash
# Setup
python -m venv .venv && source .venv/bin/activate
make setup

# Full pipeline
make all

# API server
./scripts/run_api.sh
```

### Docker
```bash
# Build images
docker build -t techitfactory/churn-ml:0.1.0 -f docker/Dockerfile.ml .
docker build -t techitfactory/churn-api:0.1.0 -f docker/Dockerfile.api .

# Run seed job
docker run --rm -v $(pwd)/data:/app/data -v $(pwd)/artifacts:/app/artifacts techitfactory/churn-ml:0.1.0 bash -c "./scripts/generate_data.sh && ./scripts/build_features.sh && ./scripts/train_baseline.sh && ./scripts/promote_model.sh"
```

### Kubernetes (Minikube)
```bash
# Deploy
kubectl apply -f k8s/

# Seed model
kubectl -n churn-mlops logs -f job/churn-seed-model

# Access API
kubectl -n churn-mlops port-forward svc/churn-api 8000:8000
```

---

## 🎓 Learning Approach

Each section follows this pattern:

1. **Goal** - What you'll accomplish
2. **Files Involved** - Exact paths and their purpose
3. **Implementation Details** - How the code works
4. **Run Commands** - Step-by-step execution
5. **Verification** - How to validate success
6. **Troubleshooting** - Common issues and fixes

---

## 🔄 MLOps Lifecycle Flow

```
┌─────────────────┐
│  Data Source    │  Generate synthetic user & event data
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Validation     │  Quality gates (schema, integrity)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Preparation    │  Clean, aggregate to user_daily
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Features       │  Rolling windows, engagement metrics
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Labels         │  Churn labels (30d future activity)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Training       │  Time-split, logistic regression
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Model Registry │  Versioned artifacts + production alias
└────────┬────────┘
         │
         ├──────────────────┐
         │                  │
         ▼                  ▼
┌─────────────────┐  ┌─────────────────┐
│  Batch Scoring  │  │  Real-time API  │
└────────┬────────┘  └────────┬────────┘
         │                    │
         ▼                    ▼
┌─────────────────────────────────┐
│     Monitoring & Drift          │
│  - Data distribution shifts     │
│  - Model performance tracking   │
│  - Trigger retraining           │
└─────────────────────────────────┘
```

---

## 🛠️ Technology Stack

- **Language**: Python 3.10+
- **ML**: scikit-learn, pandas, numpy
- **API**: FastAPI, uvicorn
- **Monitoring**: Prometheus metrics
- **Containers**: Docker
- **Orchestration**: Kubernetes (Minikube for dev)
- **Code Quality**: ruff, black, pytest
- **Config**: YAML-based configuration
- **Data Format**: CSV (easy to inspect and debug)

---

## 📝 Notes for Instructors

- All code is **production-ready** with error handling
- Files reference **actual paths** in this repository
- Commands are **copy-paste friendly**
- Troubleshooting sections cover **real issues** encountered during development
- Each section is **self-contained** but builds on previous sections
- Students can run locally, in Docker, or on Kubernetes

---

## 🤝 Contributing to These Notes

If you find issues or have suggestions:
1. These notes are **documentation only** - do not modify code
2. Keep explanations **tied to actual implementation**
3. Add troubleshooting tips based on **real experiences**
4. Maintain the **section-wise structure**

---

**Ready to begin?** Start with [Section 00: Overview](section-00-overview.md)
