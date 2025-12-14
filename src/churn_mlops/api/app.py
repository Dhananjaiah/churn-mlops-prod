from __future__ import annotations

import os
from pathlib import Path
from typing import Any, Dict, Optional

import joblib
import pandas as pd
from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from pydantic import BaseModel, Field

from churn_mlops.common.config import load_config
from churn_mlops.monitoring.api_metrics import PREDICTION_COUNT, metrics_middleware

app = FastAPI(title="TechITFactory Churn API", version="0.1.0")

# -------------------------
# Metrics middleware
# -------------------------
app.middleware("http")(metrics_middleware())

# -------------------------
# Config + paths
# -------------------------
CONFIG_PATH_ENV = "CHURN_MLOPS_CONFIG"
_model = None
_model_meta: Dict[str, Any] = {}


def _get_config() -> Dict[str, Any]:
    # load_config() already reads from CHURN_MLOPS_CONFIG env var
    return load_config()


def _production_model_path(cfg: Dict[str, Any]) -> Path:
    # Stable alias expected in prod
    p = cfg["paths"]["models"]
    return Path(p) / "production_latest.joblib"


def _load_model_or_raise(cfg: Dict[str, Any]):
    global _model, _model_meta
    model_path = _production_model_path(cfg)
    if not model_path.exists():
        raise FileNotFoundError(
            f"Missing production model alias: {model_path}. Run promote step (or seed job) first."
        )
    _model = joblib.load(model_path)
    _model_meta = {"model_path": str(model_path)}


@app.on_event("startup")
def startup_event():
    cfg = _get_config()
    try:
        _load_model_or_raise(cfg)
    except Exception as e:
        # We don't crash the process here to allow /live
        # but /ready should fail until model is present
        _model_meta = {"startup_error": str(e)}


# -------------------------
# Schemas
# -------------------------
class PredictRequest(BaseModel):
    user_id: str = Field(..., description="Unique user id")
    snapshot_date: Optional[str] = Field(None, description="Optional ISO date")
    features: Dict[str, float] = Field(..., description="Feature map for this user")


class PredictResponse(BaseModel):
    user_id: str
    churn_risk: float
    model_path: str


# -------------------------
# Health endpoints
# -------------------------
@app.get("/live")
def live():
    return {"status": "live"}


@app.get("/ready")
def ready():
    cfg = _get_config()
    try:
        if _model is None:
            _load_model_or_raise(cfg)
        return {"status": "ready", "model": _model_meta.get("model_path")}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@app.get("/health")
def health():
    # Backward compatible single health endpoint
    return ready()


# -------------------------
# Metrics endpoint
# -------------------------
@app.get("/metrics")
def metrics():
    data = generate_latest()
    return Response(content=data, media_type=CONTENT_TYPE_LATEST)


# -------------------------
# Prediction
# -------------------------
@app.post("/predict", response_model=PredictResponse)
def predict(req: PredictRequest):
    cfg = _get_config()
    try:
        if _model is None:
            _load_model_or_raise(cfg)
        # Convert feature dict -> dataframe
        x = pd.DataFrame([req.features])
        proba = float(_model.predict_proba(x)[:, 1])
        PREDICTION_COUNT.inc()
        return PredictResponse(
            user_id=req.user_id,
            churn_risk=proba,
            model_path=str(_production_model_path(cfg)),
        )
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
