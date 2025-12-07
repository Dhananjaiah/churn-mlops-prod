# Section 04: Data Validation Gates

## Goal

Implement quality checks to prevent bad data from entering the ML pipeline. Validation gates ensure schema compliance, referential integrity, and business rule adherence.

---

## Why Validation Matters

**Without Validation**:
- Training fails midway due to missing columns
- Models trained on corrupted data → poor predictions
- Silent errors (e.g., negative watch_minutes) → biased features

**With Validation**:
- **Fail fast**: Catch errors at data ingestion
- **Clear errors**: Human-readable messages
- **Confidence**: Know data quality before training

---

## Validation Strategy

```
Raw Data → Validation Gates → Processed Data → Features → Training
           ↓
           Exit 1 if errors detected
```

**Philosophy**: It's better to stop the pipeline than to train on bad data.

---

## File: `src/churn_mlops/data/validate.py`

### Validation Checks

#### Users Table

```python
def validate_users(users):
    errors = []
    
    # 1. Required columns
    required = ["user_id", "signup_date", "plan", "is_paid", "country", "marketing_source"]
    missing = [c for c in required if c not in users.columns]
    if missing:
        errors.append(f"users: missing columns: {missing}")
    
    # 2. user_id unique + no nulls
    if users["user_id"].isna().any():
        errors.append("users: 'user_id' has nulls")
    if users["user_id"].duplicated().any():
        errors.append("users: duplicate 'user_id' found")
    
    # 3. signup_date parseable
    try:
        pd.to_datetime(users["signup_date"], errors="raise")
    except:
        errors.append("users: invalid date values in 'signup_date'")
    
    # 4. plan values
    bad_plan = users.loc[~users["plan"].isin(["free", "paid"]), "plan"].unique()
    if len(bad_plan) > 0:
        errors.append(f"users: invalid plan values: {bad_plan}")
    
    # 5. is_paid must be 0/1
    bad_paid = users.loc[~users["is_paid"].isin([0, 1]), "is_paid"].unique()
    if len(bad_paid) > 0:
        errors.append(f"users: invalid is_paid values: {bad_paid}")
    
    # 6. Optional: engagement_score in [0, 1]
    if "engagement_score" in users.columns:
        if ((users["engagement_score"] < 0) | (users["engagement_score"] > 1)).any():
            errors.append("users: 'engagement_score' must be between 0 and 1")
    
    return ValidationResult(ok=len(errors) == 0, errors=errors)
```

#### Events Table

```python
def validate_events(events, users):
    errors = []
    
    # 1. Required columns
    required = ["event_id", "user_id", "event_time", "event_type", "course_id", 
                "watch_minutes", "quiz_score", "amount"]
    missing = [c for c in required if c not in events.columns]
    if missing:
        errors.append(f"events: missing columns: {missing}")
    
    # 2. event_id unique + no nulls
    if events["event_id"].isna().any():
        errors.append("events: 'event_id' has nulls")
    if events["event_id"].duplicated().any():
        errors.append("events: duplicate 'event_id' found")
    
    # 3. user_id referential integrity
    user_ids = set(users["user_id"].dropna().astype(int))
    bad_users = sorted(set(events["user_id"].astype(int)) - user_ids)
    if bad_users:
        errors.append(f"events: unknown user_id(s) not in users: {bad_users[:20]}")
    
    # 4. event_time parseable
    try:
        pd.to_datetime(events["event_time"], errors="raise")
    except:
        errors.append("events: invalid datetime values in 'event_time'")
    
    # 5. event_type allowed
    EVENT_TYPES = {"login", "course_enroll", "video_watch", "quiz_attempt",
                   "payment_success", "payment_failed", "support_ticket"}
    bad_types = events.loc[~events["event_type"].isin(EVENT_TYPES), "event_type"].unique()
    if len(bad_types) > 0:
        errors.append(f"events: invalid event_type values: {bad_types}")
    
    # 6. watch_minutes >= 0
    wm = pd.to_numeric(events["watch_minutes"], errors="coerce").fillna(0)
    if (wm < 0).any():
        errors.append("events: watch_minutes must be >= 0")
    
    # 7. quiz_score in [0, 100]
    qs = pd.to_numeric(events["quiz_score"], errors="coerce")
    bad_qs = qs.dropna().loc[(qs < 0) | (qs > 100)]
    if not bad_qs.empty:
        errors.append("events: quiz_score must be between 0 and 100")
    
    # 8. Payment events must have amount > 0
    pay_mask = events["event_type"].isin(["payment_success", "payment_failed"])
    amt = pd.to_numeric(events["amount"], errors="coerce")
    if pay_mask.any():
        bad_pay_amt = amt.loc[pay_mask].dropna().loc[amt.loc[pay_mask] <= 0]
        if not bad_pay_amt.empty:
            errors.append("events: payment events must have amount > 0")
    
    return ValidationResult(ok=len(errors) == 0, errors=errors)
```

---

## Validation Result

```python
@dataclass
class ValidationResult:
    ok: bool
    errors: List[str]
```

**Exit Code**:
```python
if result.ok:
    logger.info("RAW DATA VALIDATION PASSED ✅")
    sys.exit(0)
else:
    logger.error("RAW DATA VALIDATION FAILED ❌")
    for err in result.errors:
        logger.error(" - %s", err)
    sys.exit(1)
```

---

## Validation Rules Summary

### Users

| Rule | Check | Example Violation |
|------|-------|-------------------|
| **Schema** | Required columns present | Missing `user_id` |
| **Uniqueness** | `user_id` unique | Duplicate user_id=101 |
| **Nulls** | `user_id` has no nulls | `user_id` = NaN |
| **Dates** | `signup_date` parseable | "2025-13-45" (invalid date) |
| **Enum** | `plan` in ["free", "paid"] | plan = "premium" |
| **Range** | `is_paid` in [0, 1] | is_paid = 2 |

### Events

| Rule | Check | Example Violation |
|------|-------|-------------------|
| **Schema** | Required columns present | Missing `event_type` |
| **Uniqueness** | `event_id` unique | Duplicate event_id=1234 |
| **Referential Integrity** | `user_id` exists in users | user_id=9999 not in users |
| **Timestamps** | `event_time` parseable | "invalid_timestamp" |
| **Enum** | `event_type` in allowed set | event_type = "unknown" |
| **Range** | `watch_minutes` >= 0 | watch_minutes = -10 |
| **Range** | `quiz_score` in [0, 100] | quiz_score = 150 |
| **Business Rule** | Payment events have amount > 0 | payment_success with amount = 0 |

---

## When to Run Validation

### Option 1: After Data Generation (Synthetic)
```bash
./scripts/generate_data.sh
./scripts/validate_data.sh  # ← Validate here
./scripts/prepare_data.sh
```

### Option 2: On Data Ingestion (Production)
```python
# Ingest from S3, database, etc.
users, events = fetch_data()

# Validate immediately
result = validate_all(users, events)
if not result.ok:
    send_alert(result.errors)
    raise ValueError("Data validation failed")

# Continue processing
prepare_dataset(users, events)
```

---

## Files Involved

| File | Purpose |
|------|---------|
| `src/churn_mlops/data/validate.py` | Validation logic |
| `scripts/validate_data.sh` | Shell wrapper |
| `data/raw/users.csv` | Input (users) |
| `data/raw/events.csv` | Input (events) |

---

## Run Commands

```bash
# Validate raw data
python -m churn_mlops.data.validate

# Using script
./scripts/validate_data.sh

# With custom paths
python -m churn_mlops.data.validate --raw-dir data/raw
```

---

## Verify Steps

```bash
# 1. Run validation on good data (should pass)
./scripts/generate_data.sh
./scripts/validate_data.sh
echo $?  # Exit code 0

# 2. Introduce error (e.g., corrupt user_id)
python -c "
import pandas as pd
df = pd.read_csv('data/raw/users.csv')
df.loc[0, 'user_id'] = None  # Introduce null
df.to_csv('data/raw/users.csv', index=False)
"

# 3. Run validation again (should fail)
./scripts/validate_data.sh
echo $?  # Exit code 1

# 4. Check error messages
# Expected: "users: 'user_id' has nulls"
```

---

## Extending Validation

### Add Custom Business Rules

```python
# Example: Users must have at least 1 event
def validate_user_has_events(users, events):
    users_with_events = set(events["user_id"].unique())
    users_all = set(users["user_id"].unique())
    
    orphan_users = users_all - users_with_events
    if orphan_users:
        return f"users: {len(orphan_users)} users have no events"
    return None
```

### Add to Pipeline

```python
def validate_all(raw_dir):
    users, events = read_raw(raw_dir)
    
    ru = validate_users(users)
    re = validate_events(events, users)
    
    # Custom checks
    custom_errors = []
    err = validate_user_has_events(users, events)
    if err:
        custom_errors.append(err)
    
    all_errors = ru.errors + re.errors + custom_errors
    return ValidationResult(ok=len(all_errors) == 0, errors=all_errors)
```

---

## Integration with CI/CD

```yaml
# .github/workflows/validate.yml
name: Data Validation

on: [push]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Setup Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.10'
      - name: Install dependencies
        run: pip install -r requirements/base.txt
      - name: Generate test data
        run: python -m churn_mlops.data.generate_synthetic --n-users 100 --days 30
      - name: Validate data
        run: python -m churn_mlops.data.validate
```

---

## Troubleshooting

**Issue**: Validation passes but training fails
- **Cause**: Missing validation for a specific edge case
- **Fix**: Add validation rule for that case

**Issue**: False positives (valid data rejected)
- **Cause**: Overly strict validation rules
- **Fix**: Relax rule or make it a warning instead of error

**Issue**: Validation too slow
- **Cause**: Large datasets + expensive checks (e.g., full cross-join)
- **Fix**: Sample data for validation or optimize checks (use sets, not loops)

**Issue**: Cryptic error messages
- **Cause**: Generic validation messages
- **Fix**: Add specific error messages with examples

---

## Best Practices

1. **Fail fast**: Validate at the earliest stage possible
2. **Clear messages**: Include column names, example bad values
3. **Comprehensive**: Cover schema, nulls, types, ranges, business rules
4. **Efficient**: Use vectorized pandas operations, not row-by-row loops
5. **Version control**: Treat validation rules as code (review, test, document)

---

## Next Steps

- **[Section 05](section-05-feature-engineering.md)**: Feature engineering from validated data
- **[Section 03](section-03-data-design.md)**: Data schema reference

---

## Key Takeaways

1. **Validation gates prevent garbage-in-garbage-out**
2. **Referential integrity is critical** (user_id in events must exist in users)
3. **Business rules matter** (e.g., payment events must have amount > 0)
4. **Exit codes signal success/failure** for pipeline orchestration
5. **Validation is code**: test it, version it, improve it over time
