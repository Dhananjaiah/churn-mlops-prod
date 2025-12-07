# Section 01: Understanding Churn

## Goal

Define churn in the context of an e-learning platform, understand the business impact, and establish the ML problem formulation.

---

## What is Churn?

**Churn** (also called **attrition**) occurs when a customer stops using a product or service.

### In E-Learning Context

For **TechITFactory**, churn means:
- A user **stops logging in** to the platform
- A user **stops watching videos** or taking quizzes
- A user **cancels their subscription** (for paid users)
- A user becomes **inactive** for an extended period

**Key Insight**: Churn is not always a single event (like cancellation). It's often a gradual decline in engagement.

---

## Why Predicting Churn Matters

### Business Impact

1. **Revenue Loss**
   - Paid users who churn = direct revenue loss
   - Free users who churn = lost opportunity for conversion

2. **Customer Acquisition Cost (CAC)**
   - Acquiring a new customer costs 5-25x more than retaining one
   - Predicting churn early enables **proactive retention**

3. **Product Insights**
   - High churn cohorts reveal product or content gaps
   - Early churn signals (e.g., "no video watch in first 7 days") inform onboarding improvements

### Intervention Strategies

Once we identify high-risk users, the business can:
- **Personalized outreach**: Email campaigns, in-app notifications
- **Discount offers**: Special pricing for users at risk
- **Content recommendations**: Suggest relevant courses to re-engage
- **Support escalation**: Proactive help for struggling users

---

## ML Problem Formulation

### Supervised Learning: Binary Classification

**Input**: User features at a point in time (as_of_date)
- Demographics: `plan`, `country`, `marketing_source`, `days_since_signup`
- Engagement: `active_days_7d`, `logins_7d`, `watch_minutes_14d`, `quiz_avg_score_30d`
- Payment behavior: `payment_success_30d`, `payment_failed_30d`

**Output**: Churn probability (0.0 to 1.0)
- 0.0 = very likely to stay active
- 1.0 = very likely to churn

**Label Definition** (critical decision):
```python
churn_label = 1  if  future_active_days_in_next_30d == 0  else  0
```

### Why 30 Days?

- **Too short (e.g., 7 days)**: Noisy signal, users may just be on vacation
- **Too long (e.g., 90 days)**: Delayed intervention, harder to recover user
- **30 days**: Balances signal quality and actionability

---

## Types of Churn

### 1. **Voluntary Churn**
- User actively decides to leave (cancels subscription, deletes account)
- Often driven by: price, dissatisfaction, competition

### 2. **Involuntary Churn**
- User is removed due to payment failure, policy violation
- Preventable with better payment retry logic

### 3. **Passive Churn** (focus of this system)
- User doesn't cancel but stops engaging
- Harder to detect without behavior tracking
- Our system predicts this by monitoring activity patterns

---

## Data Requirements

To predict churn, we need:

### Event Data
```csv
event_id,user_id,event_time,event_type,course_id,watch_minutes,quiz_score,amount
1,101,2025-01-01 08:30:00,login,,,0.0,,
2,101,2025-01-01 08:35:00,video_watch,k8s-mastery,,45.0,,
3,101,2025-01-01 09:00:00,quiz_attempt,k8s-mastery,,,85.0,
4,102,2025-01-01 10:00:00,payment_success,,,,,499.00
```

### User Data
```csv
user_id,signup_date,plan,is_paid,country,marketing_source
101,2024-11-15,paid,1,IN,organic
102,2024-12-01,free,0,US,referral
```

### Derived Tables
- **user_daily**: One row per (user_id, date) with daily aggregates
- **user_features_daily**: Rolling features for each user-date
- **labels_daily**: Churn labels for each user-date (excluding last 30 days)
- **training_dataset**: Features + labels joined for model training

---

## Implementation in This Repo

### Label Creation Logic

**File**: `src/churn_mlops/training/build_labels.py`

```python
def build_labels(user_daily: pd.DataFrame, churn_window_days: int) -> pd.DataFrame:
    """
    For each user-date, count future active days in the next `churn_window_days`.
    If future_active_days == 0, churn_label = 1.
    """
    for _uid, g in user_daily.groupby("user_id", sort=False):
        active = g["is_active_day"].to_numpy()
        future_sum = _compute_future_active_sum(active, churn_window_days)
        
        tmp["churn_label"] = (tmp["future_active_days"] == 0).astype(int)
        
        # Remove last `churn_window_days` rows (we don't have future data for them)
        if len(tmp) > churn_window_days:
            tmp = tmp.iloc[:-churn_window_days]
```

**Key Insight**: We cannot label the last 30 days of data because we don't know the future. This is called **label leakage prevention**.

---

## Churn Rate Analysis

### Expected Distribution

In our synthetic data:
- Base churn rate: ~35% (configurable via `--churn-base-rate`)
- Engagement effect: High-engagement users churn less
- Plan effect: Paid users churn slightly less than free users

### Observed in Training Data

After running `./scripts/build_labels.sh`, check:
```bash
python -c "
import pandas as pd
labels = pd.read_csv('data/processed/labels_daily.csv')
print(f'Total samples: {len(labels)}')
print(f'Churn rate: {labels[\"churn_label\"].mean():.2%}')
print(f'Churned users: {labels[\"churn_label\"].sum()}')
"
```

**Expected Output**:
```
Total samples: ~200,000
Churn rate: 30-40%
Churned users: ~60,000-80,000
```

---

## Class Imbalance Handling

Churn datasets are often **imbalanced**:
- Majority class: users who stay (60-70%)
- Minority class: users who churn (30-40%)

### Strategies Used

1. **Class Weights** (in `train_baseline.py`):
   ```python
   LogisticRegression(class_weight="balanced")
   ```
   - Automatically adjusts for imbalance
   - Penalizes misclassifying minority class more

2. **Evaluation Metrics**:
   - **PR-AUC** (Precision-Recall AUC): Better for imbalanced data than accuracy
   - **ROC-AUC**: Standard metric, still useful
   - **Precision@K**: "Of the top 50 predicted churners, how many actually churned?"

3. **Time-based Split** (not random):
   - Train on older data, test on recent data
   - Respects temporal nature of churn

---

## Domain-Specific Features

Our feature engineering focuses on **engagement decline patterns**:

### Activity Trends
- `active_days_7d` vs `active_days_30d`: Is user becoming less active?
- `days_since_last_activity`: How long since last login?

### Content Engagement
- `watch_minutes_14d`: Video consumption dropping?
- `quiz_attempts_7d`: Still taking quizzes?
- `quiz_avg_score_30d`: Performance declining?

### Payment Signals
- `payment_failed_30d`: Payment issues = involuntary churn risk
- `payment_fail_rate_30d`: Ratio of failed to total payment attempts

### Static Attributes
- `plan`: Free vs. Paid
- `days_since_signup`: New users churn faster (onboarding issue)
- `country`, `marketing_source`: Cohort-specific churn patterns

---

## Churn Prediction Timeline

```
Today (as_of_date)
    │
    ├─────────── Historical Data (used for features) ───────────┤
    │  ← 30d →  ← 14d →  ← 7d →                                 │
    │                                                            │
    │  [Rolling features computed from past activity]           │
    │                                                            │
    ▼                                                            ▼
[Make Prediction]                                    [Training cutoff]
    │
    ├──────────── Future Window (30d) ────────────┤
    │                                              │
    │  If user has 0 active days here,            │
    │  churn_label = 1                            │
    │                                              │
    ▼                                              ▼
[Intervention]                              [Label revealed]
(send offer, outreach)                      (for monitoring)
```

---

## Real-World Considerations

### Data Quality
- **Missing events**: User on mobile app but events not logged
- **Bots**: Automated activity that looks like engagement
- **Seasonality**: Summer churn in education vs. holiday churn in e-commerce

### Label Ambiguity
- What if user churns then returns? (Re-churn?)
- What about users who only signed up but never activated?

### Business Constraints
- **Intervention cost**: Can't contact every user, must prioritize
- **Fatigue**: Too many retention emails = spam
- **Timing**: Intervene too early (user isn't actually churning) or too late (already gone)

---

## Verification Steps

After understanding the problem, verify:

1. **Label Distribution**:
   ```bash
   python -c "
   import pandas as pd
   labels = pd.read_csv('data/processed/labels_daily.csv')
   print(labels['churn_label'].value_counts(normalize=True))
   "
   ```

2. **Temporal Split**:
   - Training data: Earlier dates
   - Test data: Later dates
   - No data leakage

3. **Business Alignment**:
   - 30-day window makes sense for e-learning
   - Features capture meaningful engagement patterns

---

## Common Mistakes to Avoid

1. **Label Leakage**: Using future information in features
   - ❌ `total_logins_all_time` (includes future activity)
   - ✅ `logins_30d` (only past 30 days)

2. **Random Train/Test Split**: Breaks temporal ordering
   - ❌ `train_test_split(shuffle=True)`
   - ✅ Time-based split (train on early dates, test on late dates)

3. **Ignoring Class Imbalance**: Optimizing for accuracy
   - ❌ Accuracy = 70% (by predicting all "not churned")
   - ✅ PR-AUC, ROC-AUC, Precision@K

4. **Over-complicated Labels**: Multiple churn types, complex rules
   - ❌ "Partial churn", "at-risk", "dormant", "lapsed"
   - ✅ Binary: churned or not (based on clear activity threshold)

---

## Files Involved

| File | Purpose |
|------|---------|
| `src/churn_mlops/training/build_labels.py` | Label creation logic |
| `data/processed/user_daily.csv` | Daily activity aggregates (input) |
| `data/processed/labels_daily.csv` | Churn labels (output) |
| `config/config.yaml` | `churn.window_days: 30` parameter |

---

## Run Commands

```bash
# Generate synthetic data with specific churn rate
python -m churn_mlops.data.generate_synthetic --churn-base-rate 0.35

# Create labels
python -m churn_mlops.training.build_labels --window-days 30

# Inspect
head -n 20 data/processed/labels_daily.csv
```

---

## Troubleshooting

**Issue**: Churn rate too low or too high
- **Check**: `--churn-base-rate` in data generation
- **Fix**: Regenerate data with adjusted rate

**Issue**: Not enough samples in test set
- **Check**: Total date range in data
- **Fix**: Increase `--days` in data generation (e.g., 180 instead of 120)

**Issue**: All users labeled as churned
- **Check**: `future_active_days` calculation
- **Fix**: Ensure `is_active_day` is computed correctly in `user_daily`

---

## Next Steps

- **[Section 02](section-02-repo-blueprint-env.md)**: Repository structure and environment setup
- **[Section 04](section-04-data-validation-gates.md)**: Data quality validation
- **[Section 05](section-05-feature-engineering.md)**: Feature engineering details

---

## References

- **Churn Prediction Literature**: https://dl.acm.org/doi/10.1145/2834892
- **Class Imbalance**: https://machinelearningmastery.com/tactics-to-combat-imbalanced-classes-in-your-machine-learning-dataset/
- **Time Series Validation**: https://scikit-learn.org/stable/modules/cross_validation.html#time-series-split
