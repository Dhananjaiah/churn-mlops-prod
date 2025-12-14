from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List

import numpy as np
import pandas as pd


@dataclass
class DriftReport:
    psi_by_feature: Dict[str, float]
    overall_max_psi: float
    status: str  # OK / WARN / FAIL


def _psi(expected: np.ndarray, actual: np.ndarray, buckets: int = 10) -> float:
    # Handle empty arrays safely
    if len(expected) == 0 or len(actual) == 0:
        return 0.0

    # Bin edges based on expected distribution quantiles
    quantiles = np.linspace(0, 1, buckets + 1)
    edges = np.unique(np.quantile(expected, quantiles))
    if len(edges) < 3:
        return 0.0

    def _bucket_counts(x: np.ndarray) -> np.ndarray:
        counts, _ = np.histogram(x, bins=edges)
        pct = counts / max(counts.sum(), 1)
        # avoid zeros
        return np.clip(pct, 1e-6, 1.0)

    e_pct = _bucket_counts(expected)
    a_pct = _bucket_counts(actual)

    return float(np.sum((a_pct - e_pct) * np.log(a_pct / e_pct)))


def compute_drift(
    baseline_path: Path,
    current_path: Path,
    feature_cols: List[str],
    warn_psi: float = 0.1,
    fail_psi: float = 0.25,
) -> DriftReport:
    base = pd.read_csv(baseline_path)
    cur = pd.read_csv(current_path)

    psi_by = {}
    for col in feature_cols:
        if col not in base.columns or col not in cur.columns:
            continue
        e = base[col].dropna().to_numpy(dtype=float)
        a = cur[col].dropna().to_numpy(dtype=float)
        psi_by[col] = _psi(e, a)

    max_psi = max(psi_by.values(), default=0.0)

    if max_psi >= fail_psi:
        status = "FAIL"
    elif max_psi >= warn_psi:
        status = "WARN"
    else:
        status = "OK"

    return DriftReport(psi_by_feature=psi_by, overall_max_psi=max_psi, status=status)
