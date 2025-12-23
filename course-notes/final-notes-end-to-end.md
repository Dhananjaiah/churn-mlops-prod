# Final Notes (End to End)

This document explains the **full churn MLOps lifecycle implemented in this repo**, from synthetic data generation all the way to monitoring and scheduled retraining.

It is intentionally “code-first”: every step below references the exact module/script and the exact files it reads/writes.

---

## 0) The Big Picture

The pipeline is:

1. Generate synthetic raw data (users + events)
2. Validate raw data (schema + business rules)
3. Prepare processed tables (clean + daily aggregates)
4. Build features (rolling windows + recency)
5. Build labels (forward-looking churn label)
6. Build training dataset (join features + labels)
7. Train models (baseline + optional candidate)
8. Promote a model to “production alias”
9. Batch score users (writes predictions)
10. Monitor
    - data drift check (PSI)
    - score proxy (distribution of predicted scores)
11. Retrain (weekly CronJob in Kubernetes)

Local orchestration is exposed via the [Makefile](../Makefile) target `make all`.

---

## 1) Configuration: where files go

Most Python modules use the YAML config loaded by `churn_mlops.common.config.load_config()`.

- Container-style default config: [config/config.yaml](../config/config.yaml)
- Default config copy: [configs/config.yaml](../configs/config.yaml)

The key concept is the `paths` section:

- `paths.raw` → raw CSVs
- `paths.processed` → cleaned/aggregated CSVs
- `paths.features` → engineered features + training_dataset
- `paths.models` → trained models (joblib)
- `paths.metrics` → evaluation metrics + drift/proxy JSON
- `paths.predictions` → batch scoring outputs
- `paths.artifacts` → “artifacts root” (models/metrics/registry)

In many scripts, you can override config resolution by setting `CHURN_MLOPS_CONFIG=/path/to/config.yaml`.

---

## 2) Data Generation (Synthetic)

**Module:** [src/churn_mlops/data/generate_synthetic.py](../src/churn_mlops/data/generate_synthetic.py)

### What it does
Generates a synthetic e-learning dataset with:
- `users.csv`: user attributes + latent engagement
- `events.csv`: event stream (login/watch/quiz/payment/support) over a date range

Key implementation details:
- Users are created in `_build_users()` with columns:
  - `user_id`, `signup_date`, `plan`, `is_paid`, `country`, `marketing_source`, `engagement_score`
- A per-user churn date is assigned in `_assign_churn_dates()`.
- Daily events are produced by `_events_for_user_day()`.
- Events get a stable `event_id` inserted after sorting.

### Inputs
- Config: `paths.raw` for output directory.
- CLI args (defaults): `--n-users 2000`, `--days 120`, `--start-date 2025-01-01`, `--seed 42`, `--paid-ratio 0.35`, `--churn-base-rate 0.35`.

### Outputs
Written into `paths.raw` (usually `data/raw/` locally):
- `users.csv`
- `events.csv`

### Run
- Script wrapper: `./scripts/generate_data.sh`
- Direct: `python -m churn_mlops.data.generate_synthetic`

---

## 3) Data Validation Gates

**Module:** [src/churn_mlops/data/validate.py](../src/churn_mlops/data/validate.py)

### What it does
Validates raw CSVs **before** you build processed/features/training.

Users validation (`validate_users()`):
- Required columns: `user_id`, `signup_date`, `plan`, `is_paid`, `country`, `marketing_source`
- `user_id` must be unique, non-null
- `signup_date` must parse as date
- `plan` must be `free` or `paid`
- `is_paid` must be 0/1
- Optional: `engagement_score` must be in [0,1]

Events validation (`validate_events()`):
- Required columns: `event_id`, `user_id`, `event_time`, `event_type`, `course_id`, `watch_minutes`, `quiz_score`, `amount`
- `event_id` must be unique, non-null
- `user_id` must exist in users
- `event_time` must parse as datetime
- `event_type` must be one of:
  `login`, `course_enroll`, `video_watch`, `quiz_attempt`, `payment_success`, `payment_failed`, `support_ticket`
- `watch_minutes >= 0`
- `quiz_score` if present must be in [0,100]
- `amount` rules:
  - payment_* events: amount must be > 0
  - non-payment events: amount should be empty; if >2% of all events have a non-null amount → validation fails

### Inputs
- Reads:
  - `paths.raw/users.csv`
  - `paths.raw/events.csv`

### Output
- Returns exit code 0 on pass, 1 on fail.

### Run
- Script wrapper: `./scripts/validate_data.sh`
- Direct: `python -m churn_mlops.data.validate`

---

## 4) Data Preparation (Processed Layer)

**Module:** [src/churn_mlops/data/prepare_dataset.py](../src/churn_mlops/data/prepare_dataset.py)

### What it does
Cleans raw CSVs, filters to known users, and creates a **user-day** table.

Cleaning behavior:
- `_clean_users()` normalizes:
  - `user_id` numeric
  - `signup_date` to date
  - `plan` lowercase/strip
  - `is_paid` coerced to int (or derived from plan if missing)
  - drops rows missing `user_id/signup_date/plan`, de-dups by `user_id`
- `_clean_events()` normalizes:
  - numeric ids, `event_time` datetime, `event_type` lowercase/strip
  - `watch_minutes` numeric (default 0)
  - `quiz_score` numeric
  - `amount` numeric
  - derives `event_date = event_time.dt.date`
  - drops rows missing identity fields, de-dups by `event_id`

User-day aggregation:
- `_build_user_day_grid()` creates a full `user_id × date_range` grid across min/max event dates
- `_daily_aggregates()` aggregates per user-day:
  - logins_count, enroll_count, watch_minutes_sum, quiz_attempts_count, quiz_avg_score,
    payment_success_count, payment_failed_count, support_ticket_count, total_events
- `build_user_daily()` merges the grid + daily aggregates, fills count columns with 0, computes:
  - `days_since_signup`
  - `is_active_day = (total_events > 0)`

### Inputs
- Reads:
  - `paths.raw/users.csv`
  - `paths.raw/events.csv`

### Outputs
Written into `paths.processed` (usually `data/processed/` locally):
- `users_clean.csv`
- `events_clean.csv`
- `user_daily.csv`

### Run
- Script wrapper: `./scripts/prepare_data.sh`
- Direct: `python -m churn_mlops.data.prepare_dataset`

---

## 5) Feature Engineering

**Module:** [src/churn_mlops/features/build_features.py](../src/churn_mlops/features/build_features.py)

### What it does
Builds features from `user_daily.csv`.

Base preparation (`_prep_base()`):
- Enforces types for `user_id`, `as_of_date`
- Ensures numeric columns exist (fills missing with 0)
- Leaves `quiz_avg_score` as numeric (can be NaN)

Recency:
- `_add_days_since_last_activity()` creates `days_since_last_activity` using forward-filled last active date

Rolling windows:
- `_add_rolling_features()` uses `groupby(user_id).rolling(window=w, min_periods=1).sum()` for multiple columns.
- Default windows are `DEFAULT_WINDOWS = [7, 14, 30]` unless config overrides `features.windows_days`.
- It also computes rolling mean quiz score: `quiz_avg_score_{w}d`.
- Computes `payment_fail_rate_{w_ref}d` where `w_ref=30` if available else largest window.

### Inputs
- Reads: `paths.processed/user_daily.csv`

### Output
Written into `paths.features` (usually `data/features/` locally):
- `user_features_daily.csv`

### Run
- Script wrapper: `./scripts/build_features.sh`
- Direct: `python -m churn_mlops.features.build_features`

---

## 6) Label Creation (Churn Label)

**Module:** [src/churn_mlops/training/build_labels.py](../src/churn_mlops/training/build_labels.py)

### What it does
Creates a **forward-looking** churn label using future activity.

Definition:
- For each `(user_id, as_of_date)` we compute:
  - `future_active_days` = number of active days in the next `window_days`
  - `churn_label = 1` if `future_active_days == 0` else `0`

Important implementation detail:
- The last `window_days` rows per user are dropped (cannot label without future).

### Inputs
- Reads: `paths.processed/user_daily.csv`

### Output
Written into `paths.processed`:
- `labels_daily.csv`

### Run
- Script wrapper: `./scripts/build_labels.sh`
- Direct: `python -m churn_mlops.training.build_labels`

---

## 7) Training Dataset (Join Features + Labels)

**Module:** [src/churn_mlops/training/build_training_set.py](../src/churn_mlops/training/build_training_set.py)

### What it does
Inner join features and labels on `(user_id, as_of_date)` and writes a training dataset.

### Inputs
- Reads:
  - `paths.features/user_features_daily.csv`
  - `paths.processed/labels_daily.csv`

### Output
Written into `paths.features`:
- `training_dataset.csv` (contains `churn_label`)

### Run
- Script wrapper: `./scripts/build_training_set.sh`
- Direct: `python -m churn_mlops.training.build_training_set`

---

## 8) Model Training

### 8.1 Baseline model (Logistic Regression)

**Module:** [src/churn_mlops/training/train_baseline.py](../src/churn_mlops/training/train_baseline.py)

What it does:
- Time-aware train/test split by `as_of_date` (`_time_split()`)
- Preprocessing:
  - Categorical: `SimpleImputer(constant="missing")` + `OneHotEncoder(handle_unknown="ignore", sparse_output=False)`
  - Numeric: `SimpleImputer(constant=0.0)` + `StandardScaler`
- Model: `LogisticRegression(max_iter=2000, solver="lbfgs")`
- Optional imbalance handling: if `training.imbalance_strategy == "class_weight"` → `class_weight="balanced"`

Outputs:
- Model artifact: `artifacts/models/baseline_logreg_<timestamp>.joblib`
- Metrics: `artifacts/metrics/baseline_logreg_<timestamp>.json`

Metrics include:
- PR-AUC (`average_precision_score`)
- ROC-AUC (`roc_auc_score`)
- confusion matrix, classification report, sample PR curve arrays

Run:
- Script wrapper: `./scripts/train_baseline.sh`
- Direct: `python -m churn_mlops.training.train_baseline`

### 8.2 Candidate model (HistGradientBoosting)

**Module:** [src/churn_mlops/training/train_candidate.py](../src/churn_mlops/training/train_candidate.py)

What it does:
- Same time-aware split idea (`_time_split()`)
- Preprocessing:
  - Categorical: impute + onehot
  - Numeric: impute only
- Model: `HistGradientBoostingClassifier(learning_rate=0.08, max_depth=6, max_iter=250)`

Outputs:
- Model artifact: `artifacts/models/candidate_hgb_<timestamp>.joblib`
- Metrics: `artifacts/metrics/candidate_hgb_<timestamp>.json`

Run:
- Script wrapper: `./scripts/train_candidate.sh`
- Direct: `python -m churn_mlops.training.train_candidate`

---

## 9) Model Promotion / “Registry”

There are **two “promotion patterns”** in this repo:

### 9.1 Local / repo-native promotion (compares baseline vs candidate)

**Module:** [src/churn_mlops/training/promote_model.py](../src/churn_mlops/training/promote_model.py)

What it does:
- Finds latest metrics file matching:
  - `baseline_logreg_*.json`
  - `candidate_hgb_*.json`
- Compares them using `evaluation.primary_metric` (default: `pr_auc`).
- Copies the winning model + metrics into `artifacts/registry/` with a promotion timestamp.
- Updates stable production alias:
  - `artifacts/models/production_latest.joblib`
- Updates registry state:
  - `artifacts/registry/model_registry.json`

Run:
- Script wrapper: `./scripts/promote_model.sh`
- Direct: `python -m churn_mlops.training.promote_model`

### 9.2 Kubernetes seed/retrain “simple promotion” (baseline only)

K8s manifests use a simpler approach:
- After training baseline, they do:
  - `cp /app/artifacts/models/baseline_logreg_*.joblib /app/artifacts/models/production_latest.joblib`

This logic is embedded in:
- [k8s/seed-model-job.yaml](../k8s/seed-model-job.yaml)
- [k8s/retrain-cronjob.yaml](../k8s/retrain-cronjob.yaml)

---

## 10) Batch Scoring

**Module:** [src/churn_mlops/inference/batch_score.py](../src/churn_mlops/inference/batch_score.py)

### What it does
- Loads `production_latest.joblib`
- Picks an `as_of_date` (defaults to latest available in features)
- Runs `predict_proba` and writes risk-ranked CSV outputs

### Inputs
- Reads:
  - `paths.features/user_features_daily.csv`
  - `paths.models/production_latest.joblib`

### Outputs
Written to `paths.predictions` (usually `data/predictions/` locally):
- `churn_predictions_<YYYY-MM-DD>.csv`
- `churn_top_<K>_<YYYY-MM-DD>.csv` (preview file; default K=50)

### Run
- Script wrapper: `./scripts/batch_score.sh`
- “latest + alias” wrapper: `./scripts/batch_score_latest.sh`

Note: `batch_score_latest.sh` runs `batch_score.sh` and then `./scripts/ensure_latest_predictions.sh` to maintain the alias file.

---

## 11) Monitoring

### 11.1 Data drift detection (PSI)

**Core PSI implementation:** [src/churn_mlops/monitoring/drift.py](../src/churn_mlops/monitoring/drift.py)

- PSI is computed by binning based on **baseline quantiles** (10 buckets by default).
- Status thresholds:
  - WARN if max PSI ≥ 0.1
  - FAIL if max PSI ≥ 0.25

**Runner:** [src/churn_mlops/monitoring/run_drift_check.py](../src/churn_mlops/monitoring/run_drift_check.py)

What it does:
- Baseline file: `paths.features/training_dataset.csv`
- Current file: `paths.features/user_features_daily.csv`
- Checks these columns (skips any missing in either file):
  - `sessions_7d`, `watch_minutes_7d`, `watch_minutes_14d`, `watch_minutes_30d`, `quiz_attempts_7d`, `quiz_avg_score_7d`
- Writes drift report JSON to:
  - `paths.metrics/data_drift_latest.json`
- Exits with code `2` if status is FAIL (useful for CronJob failure alerts)

Run:
- Script wrapper: `./scripts/check_drift.sh`
- Direct: `python -m churn_mlops.monitoring.run_drift_check`

Heads-up: `./scripts/monitor_data_drift.sh` currently calls `python -m churn_mlops.monitoring.drift` (the library module), not the runner. For an actual drift run, use `check_drift.sh`.

### 11.2 Score proxy (a “performance proxy”)

**Implementation:** [src/churn_mlops/monitoring/score_proxy.py](../src/churn_mlops/monitoring/score_proxy.py)

What it does:
- Reads a predictions CSV and summarizes the distribution of `churn_risk`:
  - mean, p50, p90, p99
  - high_risk_rate = fraction of scores ≥ threshold (default threshold = 0.7)

**Runner:** [src/churn_mlops/monitoring/run_score_proxy.py](../src/churn_mlops/monitoring/run_score_proxy.py)

Inputs:
- Reads: `paths.predictions/batch_predictions_latest.csv`

Output:
- Writes: `paths.metrics/score_proxy_latest.json`

---

## 12) Retraining

### 12.1 Kubernetes weekly retrain

Manifest: [k8s/retrain-cronjob.yaml](../k8s/retrain-cronjob.yaml)

- Schedule: Sundays at 03:00 (`0 3 * * 0`)
- Steps executed (inside the ML image):
  1) `python -m churn_mlops.data.generate_synthetic`
  2) `python -m churn_mlops.data.validate`
  3) `python -m churn_mlops.data.prepare_dataset`
  4) `python -m churn_mlops.features.build_features`
  5) `python -m churn_mlops.training.build_labels`
  6) `python -m churn_mlops.training.build_training_set`
  7) `python -m churn_mlops.training.train_baseline`
  8) Copy latest baseline model to production alias: `production_latest.joblib`

This gives you a realistic “scheduled retrain” loop.

### 12.2 Alert → retrain?

Right now the repo has:
- Drift check that can fail a Job (exit code 2)
- A weekly retrain CronJob

But **automatic event-driven retraining** (Alertmanager → webhook → trigger retrain job) is not wired by default. That would require additional glue (e.g., an Alertmanager webhook receiver, Argo Events, or similar).

---

## 13) How to run end-to-end locally

### Option A: one command

```bash
make all
```

This runs:
- data → features → labels → train → promote → batch → test → lint

### Option B: step-by-step (good for demos)

```bash
make data
make features
make labels
make train
make promote
make batch
```

---

## 14) How to demo drift FAIL (without changing code)

The drift runner compares:
- baseline: `data/features/training_dataset.csv`
- current: `data/features/user_features_daily.csv`

So the easiest demo is: **temporarily skew one drift-checked column** in `user_features_daily.csv`.

### Safe demo steps (backup + restore)

1) Ensure you have baseline + current features:

```bash
make data features labels
make train
```

2) Backup the current file:

```bash
cp data/features/user_features_daily.csv data/features/user_features_daily.backup.csv
```

3) Inject a distribution shift (example: multiply watch minutes):

```bash
python - <<'PY'
import pandas as pd
p = 'data/features/user_features_daily.csv'
df = pd.read_csv(p)
for col in ['watch_minutes_7d','watch_minutes_14d','watch_minutes_30d']:
    if col in df.columns:
        df[col] = df[col].fillna(0) * 50
# optional: shift quiz scores slightly
if 'quiz_avg_score_7d' in df.columns:
    df['quiz_avg_score_7d'] = (df['quiz_avg_score_7d'].fillna(0) * 0.2).clip(0,100)
df.to_csv(p, index=False)
print('Wrote drifted features ->', p)
PY
```

4) Run the drift check (expect FAIL / exit code 2):

```bash
./scripts/check_drift.sh
```

5) Inspect the drift report:

- `artifacts/metrics/data_drift_latest.json`

6) Restore original features:

```bash
mv data/features/user_features_daily.backup.csv data/features/user_features_daily.csv
```

If you forget to restore: rerun `make features`.

---

## 15) Where Prometheus fits

Prometheus integration is covered in:
- [Section 12A: Prometheus Monitoring & Alerts](section-12a-prometheus-monitoring-retrain.md)

In short:
- The API exposes `/metrics` (FastAPI + prometheus_client)
- Kubernetes monitoring uses `ServiceMonitor` + `PrometheusRule` **if** you install the Prometheus Operator CRDs
- Drift and score-proxy are batch jobs; you typically alert on job failures (drift FAIL) and/or periodically scrape/export their JSON metrics

---

## Appendix: What each stage reads/writes (quick table)

| Stage | Reads | Writes | Main module |
|------|-------|--------|-------------|
| Generate | config only | raw/users.csv, raw/events.csv | churn_mlops.data.generate_synthetic |
| Validate | raw/users.csv, raw/events.csv | exit code | churn_mlops.data.validate |
| Prepare | raw/* | processed/users_clean.csv, events_clean.csv, user_daily.csv | churn_mlops.data.prepare_dataset |
| Features | processed/user_daily.csv | features/user_features_daily.csv | churn_mlops.features.build_features |
| Labels | processed/user_daily.csv | processed/labels_daily.csv | churn_mlops.training.build_labels |
| Train set | features + labels | features/training_dataset.csv | churn_mlops.training.build_training_set |
| Train baseline | features/training_dataset.csv | artifacts/models + artifacts/metrics | churn_mlops.training.train_baseline |
| Train candidate | features/training_dataset.csv | artifacts/models + artifacts/metrics | churn_mlops.training.train_candidate |
| Promote | artifacts/metrics + artifacts/models | artifacts/registry + production_latest.joblib | churn_mlops.training.promote_model |
| Batch score | features/user_features_daily.csv + production model | predictions/*.csv | churn_mlops.inference.batch_score |
| Drift check | training_dataset.csv + user_features_daily.csv | artifacts/metrics/data_drift_latest.json | churn_mlops.monitoring.run_drift_check |
| Score proxy | predictions/batch_predictions_latest.csv | artifacts/metrics/score_proxy_latest.json | churn_mlops.monitoring.run_score_proxy |

