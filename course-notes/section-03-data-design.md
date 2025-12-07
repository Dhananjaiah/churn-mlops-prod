# Section 03: Data Design

## Goal

Understand the synthetic data generation system, event schema, and how raw data flows into aggregated tables.

---

## Synthetic Data Generation

### Why Synthetic Data?

1. **Privacy**: No real user PII needed for course/demo
2. **Reproducibility**: Same seed = same data
3. **Control**: Tune churn rate, engagement patterns, sample size
4. **Education**: Understand data distribution without NDA restrictions

### File: `src/churn_mlops/data/generate_synthetic.py`

**Generates**:
- `data/raw/users.csv`: 2000 users with demographics
- `data/raw/events.csv`: ~200K-500K events over 120 days

---

## Event Types

```python
EVENT_TYPES = [
    "login",               # User signs in
    "course_enroll",       # User enrolls in a course
    "video_watch",         # User watches video (with duration)
    "quiz_attempt",        # User takes quiz (with score)
    "payment_success",     # Successful payment
    "payment_failed",      # Failed payment (involuntary churn risk)
    "support_ticket",      # User contacts support
]
```

---

## User Schema

**File**: `data/raw/users.csv`

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `user_id` | int | Unique identifier | 1, 2, 3, ... |
| `signup_date` | date | When user signed up | 2024-12-01 |
| `plan` | str | `free` or `paid` | paid |
| `is_paid` | int | 1 if paid, 0 if free | 1 |
| `country` | str | User country | IN, US, UK, CA, AU, SG |
| `marketing_source` | str | Acquisition channel | organic, referral, ads, youtube, community |
| `engagement_score` | float | Latent engagement (synthetic only) | 0.65 |

**Key Design Decisions**:
- `engagement_score`: Hidden variable that drives activity level (high engagement = less churn)
- `paid_ratio`: 35% of users are paid (configurable)
- `signup_date`: Spread over 30-40 days before observation window

---

## Event Schema

**File**: `data/raw/events.csv`

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `event_id` | int | Unique event identifier | 1, 2, 3, ... |
| `user_id` | int | Foreign key to users | 101 |
| `event_time` | timestamp | When event occurred | 2025-01-01 08:30:00 |
| `event_type` | str | Type of event | login, video_watch, quiz_attempt |
| `course_id` | str | Course identifier (nullable) | k8s-mastery |
| `watch_minutes` | float | Video watch duration (nullable) | 45.0 |
| `quiz_score` | float | Quiz score 0-100 (nullable) | 85.0 |
| `amount` | float | Payment amount (nullable) | 499.00 |

**Key Design Decisions**:
- `event_id`: Globally unique, sorted by (user_id, event_time)
- Sparse columns: Only relevant fields populated per event type
- Temporal ordering: Events naturally ordered by time

---

## Course Pool

```python
COURSE_POOL = [
    "k8s-mastery",
    "devops-warrior",
    "mlops-foundation",
    "argo-cd",
    "terraform",
    "linux-pro",
    "observability",
]
```

**Realistic for TechITFactory**: DevOps/Cloud/SRE courses

---

## Data Generation Logic

### User Generation

```python
def _build_users(rng, settings):
    # 1. Generate user_ids (1 to n_users)
    user_ids = np.arange(1, settings.n_users + 1)
    
    # 2. Spread signup dates over signup_spread_days
    signup_offsets = rng.integers(0, signup_spread_days, size=settings.n_users)
    signup_dates = [start_dt - timedelta(days=int(x)) for x in signup_offsets]
    
    # 3. Assign paid/free based on paid_ratio
    is_paid = rng.random(settings.n_users) < settings.paid_ratio
    
    # 4. Random demographics
    countries = _random_choice(rng, ["IN", "US", "UK", "CA", "AU", "SG"], settings.n_users)
    sources = _random_choice(rng, ["organic", "referral", "ads", "youtube", "community"], settings.n_users)
    
    # 5. Latent engagement score (Beta distribution)
    engagement = rng.beta(a=2.0, b=2.5, size=settings.n_users)  # Slightly right-skewed
```

**Engagement Distribution**:
- Beta(2.0, 2.5) → most users have moderate engagement (0.4-0.7)
- Low tail (< 0.3) → high churn risk
- High tail (> 0.8) → power users

### Churn Assignment

```python
def _assign_churn_dates(rng, users, settings):
    for row in users.itertuples():
        base = settings.churn_base_rate  # e.g., 0.35
        
        # Paid users churn less
        if row.is_paid == 1:
            base *= 0.75
        
        # Engagement effect (dominant factor)
        engagement_factor = (1.0 - float(row.engagement_score)) ** 1.6
        churn_prob = min(0.95, base * (0.4 + 1.4 * engagement_factor))
        
        if rng.random() < churn_prob:
            # User will churn at some point during observation
            churn_offset = rng.integers(low=settings.days // 4, high=settings.days)
            churn_dt = start_dt + timedelta(days=churn_offset)
            churn_dates[user_id] = churn_dt
```

**Formula Breakdown**:
- Low engagement (e.g., 0.2): `(1-0.2)^1.6 = 0.72` → high churn prob
- High engagement (e.g., 0.8): `(1-0.8)^1.6 = 0.05` → low churn prob

### Event Generation

```python
def _events_for_user_day(rng, user_id, is_paid, engagement, day_dt):
    # 1. Decide if user is active today
    active_today = rng.random() < (0.15 + 0.8 * engagement)
    
    # 2. Generate 1-3 sessions per active day
    sessions = rng.integers(1, 4)
    for _ in range(sessions):
        # Login event
        events.append({"event_type": "login", ...})
        
        # Video watch (50-90% chance for engaged users)
        if rng.random() < (0.5 + 0.4 * engagement):
            watch_minutes = rng.normal(20 + 40 * engagement, 10)
            events.append({"event_type": "video_watch", ...})
        
        # Quiz attempt (25-60% chance)
        if rng.random() < (0.25 + 0.35 * engagement):
            quiz_score = rng.normal(50 + 40 * engagement, 15)
            events.append({"event_type": "quiz_attempt", ...})
    
    # 3. Payment events (monthly for paid users)
    if is_paid == 1 and day_dt.day in {1, 2, 3}:
        pay_success = rng.random() < 0.93
        events.append({"event_type": "payment_success" if pay_success else "payment_failed", ...})
```

**Realistic Patterns**:
- High engagement users: More logins, longer video watches, higher quiz scores
- Paid users: Monthly payment events (first 3 days of month)
- Occasional support tickets (~0.5% probability per day)

---

## Preparation Pipeline

### File: `src/churn_mlops/data/prepare_dataset.py`

**Transforms**:
```
Raw Data                     Processed Data
---------                    ---------------
users.csv                 →  users_clean.csv (deduplicated, type-corrected)
events.csv                →  events_clean.csv (validated, with event_date)
users + events            →  user_daily.csv (one row per user-date)
```

### Cleaning Steps

**Users**:
```python
def _clean_users(users):
    # 1. Parse dates
    u["signup_date"] = pd.to_datetime(u["signup_date"]).dt.date
    
    # 2. Normalize plan
    u["plan"] = u["plan"].str.lower().str.strip()
    
    # 3. Ensure is_paid matches plan
    u["is_paid"] = (u["plan"] == "paid").astype(int)
    
    # 4. Drop duplicates
    u = u.drop_duplicates(subset=["user_id"])
```

**Events**:
```python
def _clean_events(events):
    # 1. Parse timestamps
    e["event_time"] = pd.to_datetime(e["event_time"])
    e["event_date"] = e["event_time"].dt.date
    
    # 2. Normalize event_type
    e["event_type"] = e["event_type"].str.lower().str.strip()
    
    # 3. Ensure numeric columns
    e["watch_minutes"] = pd.to_numeric(e["watch_minutes"]).fillna(0.0)
    e["quiz_score"] = pd.to_numeric(e["quiz_score"])  # NaN OK
    
    # 4. Drop duplicates
    e = e.drop_duplicates(subset=["event_id"])
```

### User-Daily Aggregation

**Output**: `data/processed/user_daily.csv`

**Schema**:
```
user_id, as_of_date, signup_date, days_since_signup, plan, is_paid, country, marketing_source,
is_active_day, total_events, logins_count, enroll_count, watch_minutes_sum, quiz_attempts_count,
quiz_avg_score, payment_success_count, payment_failed_count, support_ticket_count
```

**Logic**:
```python
def build_user_daily(users, events):
    # 1. Create Cartesian grid: all users × all dates
    grid = pd.MultiIndex.from_product([user_ids, date_range])
    
    # 2. Aggregate events per (user_id, date)
    daily = events.groupby(["user_id", "event_date"]).agg({
        "event_id": "count",  # total_events
        "event_type": lambda x: (x == "login").sum(),  # logins_count
        # ... more aggregations
    })
    
    # 3. Merge grid + daily (left join, fill 0 for missing)
    merged = grid.merge(daily, how="left").fillna(0)
    
    # 4. Add user attributes
    merged = merged.merge(users[["user_id", "plan", "country", ...]])
    
    # 5. Derived columns
    merged["days_since_signup"] = (merged["as_of_date"] - merged["signup_date"]).dt.days
    merged["is_active_day"] = (merged["total_events"] > 0).astype(int)
```

**Key Insight**: Full grid ensures zero-activity days are explicit (critical for churn detection)

---

## Data Volumes

**Typical Run** (`--n-users 2000 --days 120`):
- Users: ~2,000 rows
- Events: ~200,000-500,000 rows (depends on engagement distribution)
- User-daily: ~240,000 rows (2000 users × 120 days)

**Storage**:
- Raw CSVs: ~50-100 MB
- Processed CSVs: ~30-50 MB
- Gzip compression: ~10x reduction

---

## Files Involved

| File | Purpose |
|------|---------|
| `src/churn_mlops/data/generate_synthetic.py` | Synthetic data generator |
| `src/churn_mlops/data/prepare_dataset.py` | Data cleaning & aggregation |
| `scripts/generate_data.sh` | Wrapper for generation |
| `scripts/prepare_data.sh` | Wrapper for preparation |
| `data/raw/users.csv` | Raw user data (output) |
| `data/raw/events.csv` | Raw event data (output) |
| `data/processed/users_clean.csv` | Cleaned users (output) |
| `data/processed/events_clean.csv` | Cleaned events (output) |
| `data/processed/user_daily.csv` | Daily aggregations (output) |

---

## Run Commands

```bash
# Generate synthetic data (default: 2000 users, 120 days)
python -m churn_mlops.data.generate_synthetic

# Generate with custom parameters
python -m churn_mlops.data.generate_synthetic \
  --n-users 5000 \
  --days 180 \
  --churn-base-rate 0.40 \
  --seed 42

# Prepare datasets
python -m churn_mlops.data.prepare_dataset

# Using scripts
./scripts/generate_data.sh
./scripts/prepare_data.sh

# Inspect output
head -n 10 data/raw/users.csv
head -n 10 data/raw/events.csv
wc -l data/raw/*.csv
```

---

## Verify Steps

```bash
# 1. Check file existence
ls -lh data/raw/users.csv data/raw/events.csv

# 2. Count rows
wc -l data/raw/*.csv
# Expected: ~2000 users, ~200K-500K events

# 3. Inspect schema
head -n 3 data/raw/users.csv
head -n 3 data/raw/events.csv

# 4. Check user_daily
python -c "
import pandas as pd
df = pd.read_csv('data/processed/user_daily.csv')
print(f'Rows: {len(df)}')
print(f'Users: {df[\"user_id\"].nunique()}')
print(f'Date range: {df[\"as_of_date\"].min()} to {df[\"as_of_date\"].max()}')
print(f'Active days (mean): {df[\"is_active_day\"].mean():.2%}')
"
```

---

## Troubleshooting

**Issue**: Event counts very low
- **Cause**: Low engagement_score distribution or restrictive activity probability
- **Fix**: Increase engagement Beta parameters or adjust activity threshold

**Issue**: `user_daily.csv` too large (> 1 GB)
- **Cause**: Too many users or too many days
- **Fix**: Reduce `--n-users` or `--days`

**Issue**: Missing engagement_score column in cleaned data
- **Cause**: Expected, it's synthetic-only (not in real-world data)
- **Fix**: Check if you need it; if so, preserve during cleaning

**Issue**: Churn rate 0% or 100%
- **Cause**: Bug in churn assignment logic
- **Fix**: Check `_assign_churn_dates` and ensure `churn_dates` propagates to event generation

---

## Next Steps

- **[Section 04](section-04-data-validation-gates.md)**: Data quality validation
- **[Section 05](section-05-feature-engineering.md)**: Feature engineering from user_daily

---

## Key Takeaways

1. **Synthetic data enables reproducible ML education** without privacy concerns
2. **Event schema is sparse**: Only relevant columns populated per event type
3. **User-daily table is the foundation**: All features and labels built from it
4. **Engagement score drives churn**: Hidden variable controls synthetic behavior
5. **Full date grid is critical**: Zero-activity days must be explicit for churn detection
