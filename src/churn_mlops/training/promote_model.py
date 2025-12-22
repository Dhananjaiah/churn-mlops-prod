from __future__ import annotations

import argparse
import json
import shutil
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from churn_mlops.common.config import load_config
from churn_mlops.common.logging import setup_logging
from churn_mlops.common.utils import ensure_dir


@dataclass
class PromoteSettings:
    models_dir: str
    metrics_dir: str
    registry_dir: str
    primary_metric: str


def _latest_metrics_file(metrics_dir: str, prefix: str) -> Optional[Path]:
    p = Path(metrics_dir)
    # newest first by name (works if filenames include timestamps)
    files = sorted(p.glob(f"{prefix}_*.json"), reverse=True)
    return files[0] if files else None


def _read_metrics(path: Path) -> Dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def _score(metrics: Dict[str, Any], primary: str) -> float:
    # supports both shapes:
    # 1) {"metrics": {"pr_auc": 0.12}, "artifact": "..."}
    # 2) {"pr_auc": 0.12, "artifact": "..."}
    if isinstance(metrics.get("metrics"), dict):
        v = metrics["metrics"].get(primary)
    else:
        v = metrics.get(primary)
    try:
        return float(v)
    except Exception:
        return 0.0


def _load_registry(registry_path: Path) -> Dict[str, Any]:
    if not registry_path.exists():
        return {"models": [], "production": None}
    with registry_path.open("r", encoding="utf-8") as f:
        return json.load(f)


def _save_registry(registry_path: Path, registry: Dict[str, Any]):
    with registry_path.open("w", encoding="utf-8") as f:
        json.dump(registry, f, indent=2)


def promote(settings: PromoteSettings) -> Path:
    baseline_m = _latest_metrics_file(settings.metrics_dir, "baseline_logreg")
    candidate_m = _latest_metrics_file(settings.metrics_dir, "candidate_hgb")

    if not baseline_m and not candidate_m:
        raise FileNotFoundError("No metrics found to promote.")

    contenders: List[Tuple[str, Path, Dict[str, Any]]] = []
    if baseline_m:
        contenders.append(("baseline_logreg", baseline_m, _read_metrics(baseline_m)))
    if candidate_m:
        contenders.append(("candidate_hgb", candidate_m, _read_metrics(candidate_m)))

    best_name, best_metrics_path, best_metrics = max(
        contenders, key=lambda x: _score(x[2], settings.primary_metric)
    )

    best_artifact = best_metrics.get("artifact")
    if not best_artifact:
        raise ValueError(f"Metrics file {best_metrics_path} missing 'artifact' field")

    # artifact should be just a filename (recommended)
    best_model_path = Path(settings.models_dir) / Path(best_artifact).name
    if not best_model_path.exists():
        raise FileNotFoundError(f"Model artifact missing: {best_model_path}")

    # Ensure dirs
    models_dir = Path(ensure_dir(settings.models_dir))
    registry_dir = Path(ensure_dir(settings.registry_dir))

    # Copy model + metrics INTO registry (this is what you expected)
    stamp = datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")
    reg_model = registry_dir / f"{best_name}_{stamp}.joblib"
    reg_metrics = registry_dir / f"{best_name}_{stamp}.json"

    shutil.copy2(best_model_path, reg_model)
    shutil.copy2(best_metrics_path, reg_metrics)

    # Stable production alias (in models dir)
    prod_alias = models_dir / "production_latest.joblib"
    shutil.copy2(reg_model, prod_alias)

    # Update registry JSON
    registry_path = registry_dir / "model_registry.json"
    registry = _load_registry(registry_path)

    entry = {
        "name": best_name,
        "artifact": reg_model.name,
        "metrics_file": reg_metrics.name,
        "primary_metric": settings.primary_metric,
        "primary_score": _score(best_metrics, settings.primary_metric),
        "promoted_at_utc": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    }

    registry["models"].append(entry)
    registry["production"] = entry
    _save_registry(registry_path, registry)

    return prod_alias


def parse_args() -> PromoteSettings:
    cfg = load_config()
    parser = argparse.ArgumentParser(description="Promote best churn model to production alias")

    parser.add_argument("--models-dir", type=str, default=cfg["paths"]["models"])
    parser.add_argument("--metrics-dir", type=str, default=cfg["paths"]["metrics"])

    # IMPORTANT: default registry under artifacts path (works local + docker)
    artifacts = cfg["paths"].get("artifacts", "artifacts")
    parser.add_argument("--registry-dir", type=str, default=str(Path(artifacts) / "registry"))

    args = parser.parse_args()
    primary = str(cfg.get("evaluation", {}).get("primary_metric", "pr_auc"))

    return PromoteSettings(
        models_dir=args.models_dir,
        metrics_dir=args.metrics_dir,
        registry_dir=args.registry_dir,
        primary_metric=primary,
    )


def main():
    cfg = load_config()
    logger = setup_logging(cfg)
    settings = parse_args()

    logger.info("Promoting best model using primary metric='%s'...", settings.primary_metric)
    prod_path = promote(settings)
    logger.info("Production alias updated ✅ -> %s", prod_path)


if __name__ == "__main__":
    main()
