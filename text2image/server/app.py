import base64
import torch
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Optional, List


from .model_loader import load_model

app = FastAPI()

MODEL = None
MODEL_READY = False

# ---------- Request Models ----------

class V3ImageGenerationRequest(BaseModel):
    model: str
    prompt: str
    num_inference_steps: Optional[int] = 25
    size: Optional[str] = "512x512"

# ---------- Startup ----------

@app.on_event("startup")
async def startup_event():
    global MODEL, MODEL_READY
    MODEL = load_model()
    MODEL_READY = True

# ---------- Status Endpoint ----------

@app.get("/status")
async def status():
    return {"model_loaded": MODEL_READY}

# ---------- Models Listing (OpenAI style) ----------

@app.get("/v1/models")
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

# ---------- v3 Detection-compatible Image Generation ----------

@app.post("/v3/images/generations")
async def generate_v3(req: V3ImageGenerationRequest):
    if not MODEL_READY:
        raise HTTPException(status_code=503, detail="Model not loaded")

    # Parse WxH from the size field
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

    # Convert to base64
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
