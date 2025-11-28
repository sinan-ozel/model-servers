import base64
import torch
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from typing import Optional, List

from .model_loader import load_model

app = FastAPI()

MODEL = None
MODEL_READY = False

# ---------- Request Models ----------

class V3ImageGenerationRequest(BaseModel):
    model: str = Field(
        ...,
        example="CompVis/stable-diffusion-v1-4"
    )
    prompt: str = Field(
        ...,
        example="A scenic mountain landscape painted in watercolor"
    )
    num_inference_steps: Optional[int] = Field(
        25,
        example=30
    )
    size: Optional[str] = Field(
        "512x512",
        example="768x768"
    )

    class Config:
        schema_extra = {
            "example": {
                "model": "CompVis/stable-diffusion-v1-4",
                "prompt": "A futuristic city skyline at sunset",
                "num_inference_steps": 40,
                "size": "512x512"
            }
        }

# ---------- Startup ----------

@app.on_event("startup")
async def startup_event():
    global MODEL, MODEL_READY
    MODEL = load_model()
    MODEL_READY = True

# ---------- Status Endpoint ----------

@app.get(
    "/status",
    responses={
        200: {
            "description": "Model readiness state",
            "content": {
                "application/json": {
                    "example": {"model_loaded": True}
                }
            }
        }
    }
)
async def status():
    return {"model_loaded": MODEL_READY}

# ---------- Models Listing ----------

@app.get(
    "/v1/models",
    responses={
        200: {
            "description": "List available models",
            "content": {
                "application/json": {
                    "example": {
                        "object": "list",
                        "data": [
                            {
                                "id": "CompVis/stable-diffusion-v1-4",
                                "object": "model",
                                "owned_by": "local",
                                "permission": []
                            }
                        ]
                    }
                }
            }
        }
    }
)
async def list_models():
    return {
        "object": "list",
        "data": [
            {
                "id": "CompVis/stable-diffusion-v1-4",
                "object": "model",
                "owned_by": "local",
                "permission": []
            }
        ]
    }

# ---------- v3 Images API ----------

@app.post(
    "/v3/images/generations",
    responses={
        200: {
            "description": "Image generated successfully",
            "content": {
                "application/json": {
                    "example": {
                        "data": [
                            {
                                "b64_json": "<BASE64_ENCODED_PNG>"
                            }
                        ]
                    }
                }
            }
        },
        400: {
            "description": "Invalid size format",
            "content": {
                "application/json": {
                    "example": {"detail": "Invalid size format"}
                }
            }
        },
        503: {
            "description": "Model not yet loaded",
            "content": {
                "application/json": {
                    "example": {"detail": "Model not loaded"}
                }
            }
        }
    }
)
async def generate_v3(req: V3ImageGenerationRequest):
    if not MODEL_READY:
        raise HTTPException(status_code=503, detail="Model not loaded")

    try:
        w_str, h_str = req.size.lower().split("x")
        width, height = int(w_str), int(h_str)
    except:
        raise HTTPException(status_code=400, detail="Invalid size format")

    image = MODEL(
        req.prompt,
        num_inference_steps=req.num_inference_steps,
        width=width,
        height=height
    ).images[0]

    import io
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    b64 = base64.b64encode(buffer.getvalue()).decode("utf-8")

    return {
        "data": [
            {
                "b64_json": b64
            }
        ]
    }
