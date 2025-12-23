# Section 12A: Prometheus Monitoring → Drift Alerts → Retrain Workflow (Kubernetes)

## Goal

Make monitoring **production-like** by installing Prometheus (Operator-based) in Kubernetes and wiring your churn system into it:

- **Scrape API metrics** from `/metrics`
- **Alert** on API health issues (5xx rate, latency)
- **Alert** when the **drift check CronJob fails** (PSI drift detected)
- Use alerts to **trigger retraining actions** (manual or event-driven)

This section is an implementation companion to [section-12-monitoring-retrain.md](section-12-monitoring-retrain.md). It focuses on the *Kubernetes + Prometheus wiring*.

---

## Why We Need Prometheus Installed

Your repo already includes Kubernetes resources that depend on the **Prometheus Operator CRDs**:

- `ServiceMonitor` (to tell Prometheus what to scrape)
- `PrometheusRule` (to define alerting rules)

These are **Custom Resources**. If Prometheus Operator is not installed, applying them will fail with errors like:

- `no matches for kind "ServiceMonitor" in version "monitoring.coreos.com/v1"`
- `no matches for kind "PrometheusRule" in version "monitoring.coreos.com/v1"`

So yes: you must install a Prometheus stack in the cluster first.

---

## What We Implemented in This Repo (Actual Files)

### 1) API exposes Prometheus metrics

- API `/metrics` endpoint: [src/churn_mlops/api/app.py](../src/churn_mlops/api/app.py)
- Metrics middleware + counters/histograms: [src/churn_mlops/monitoring/api_metrics.py](../src/churn_mlops/monitoring/api_metrics.py)

**What the code does**:
- The middleware wraps every request and records:
  - request counts
  - request latency histogram
- The `/predict` handler increments a prediction counter.
- `/metrics` returns Prometheus text format via `prometheus_client.generate_latest()`.

### 2) Drift detection runs on a schedule and fails the job on drift

- PSI drift calculation: [src/churn_mlops/monitoring/drift.py](../src/churn_mlops/monitoring/drift.py)
- Runner writes a JSON report and exits `2` if drift is `FAIL`: [src/churn_mlops/monitoring/run_drift_check.py](../src/churn_mlops/monitoring/run_drift_check.py)
- Kubernetes CronJob: [k8s/drift-cronjob.yaml](../k8s/drift-cronjob.yaml)

**What the code does**:
- Reads baseline vs current features CSVs
- Computes PSI per feature
- Writes `artifacts/metrics/data_drift_latest.json`
- Exits non-zero on FAIL so Kubernetes marks the Job as failed (easy to alert on)

### 3) Prometheus Operator integration via manifests

- ServiceMonitor (scrape API): [k8s/monitoring/servicemonitor.yaml](../k8s/monitoring/servicemonitor.yaml)
- PrometheusRule (alerts): [k8s/monitoring/prometheus-rules.yaml](../k8s/monitoring/prometheus-rules.yaml)
- Included into deployment: [k8s/kustomization.yaml](../k8s/kustomization.yaml)

---

## Install Prometheus on Kubernetes (Operator-Based)

You have two common production-grade options:

### Option A: kube-prometheus-stack (Helm)
This is the fastest path in many teams.

### Option B: kube-prometheus (Manifests)
This matches a “no Helm for app manifests” approach. You apply the Prometheus stack itself via vendor manifests.

This repo does not vendor those manifests, so the exact commands depend on your chosen distribution.

**Minimum requirement**: after installation, these CRDs exist:

```bash
kubectl get crd | grep -E 'servicemonitors|prometheusrules|prometheuses'
```

And you should have kube-state-metrics installed (needed for the drift CronJob failure alert rule).

---

## Deploy Your App + Monitoring Resources

Because [k8s/kustomization.yaml](../k8s/kustomization.yaml) includes the monitoring files, you can deploy everything together:

```bash
kubectl apply -k k8s/
```

If Prometheus Operator is not installed yet, apply will fail on the `ServiceMonitor` / `PrometheusRule` kinds.

---

## Validate It Works

### 1) Confirm the API is exposing metrics

```bash
kubectl -n churn-mlops port-forward svc/churn-api 8000:8000
curl -s http://localhost:8000/metrics | head
```

### 2) Confirm Prometheus is scraping the ServiceMonitor

In Prometheus UI:
- Targets should show a `churn-api` scrape target
- You should be able to query metrics like:

```promql
rate(churn_api_requests_total[5m])
```

### 3) Confirm alerts are loaded

Your alert rules are defined in: [k8s/monitoring/prometheus-rules.yaml](../k8s/monitoring/prometheus-rules.yaml)

Key alerts:
- `ChurnApiHighErrorRate`
- `ChurnApiHighLatencyP95`
- `ChurnDataDriftJobFailed`

---

## Important: Label/Selector Matching (Most Common Gotcha)

Prometheus Operator does not always scrape **all** ServiceMonitors / Rules by default.
It depends on the `Prometheus` resource’s selectors:

- `spec.serviceMonitorSelector`
- `spec.ruleSelector`

Your manifests currently include a label:
- `release: prometheus`

You must ensure your installed Prometheus instance selects that label.

**How to check** (example):

```bash
kubectl -n monitoring get prometheus -o yaml
```

Then confirm the selectors include `release: prometheus` (or update your labels to match what your Prometheus expects).

---

## How Drift → Retrain Works With Prometheus

Prometheus **does not retrain by itself**.

What Prometheus gives you:
- a reliable drift signal (alert)
- routing to Alertmanager (Slack/email/webhook)

What *you* add to complete the loop:

### Manual retrain (simple and valid)
When drift alert fires:

```bash
kubectl -n churn-mlops create job --from=cronjob/churn-retrain-weekly retrain-now-$(date +%s)
```

### Event-driven retrain (more production)
Alertmanager webhook → Argo Events / Workflow / CI runner → start retrain job.

This repo currently implements the **monitoring + alerting** pieces; the “automatic retrain trigger” requires an eventing mechanism.

---

## Troubleshooting

### `ServiceMonitor`/`PrometheusRule` kind not found
Prometheus Operator is not installed (CRDs missing).

### No targets scraped
- Service label mismatch (`spec.selector.matchLabels` vs Service labels)
- Prometheus `serviceMonitorSelector` label mismatch

### Drift-job alert never fires
- Drift CronJob isn’t failing (check Job status)
- `kube-state-metrics` not installed, so `kube_job_status_failed` is missing

---

## Summary

- Yes: you must install Prometheus Operator in Kubernetes for `ServiceMonitor`/`PrometheusRule`.
- Your API metrics + drift CronJob already exist.
- We added manifest-level wiring so Prometheus can scrape and alert.
- “Alert → retrain automatically” requires Alertmanager routing + an event trigger system (or manual job trigger).
