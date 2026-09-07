from typing import Optional

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import Response
from pydantic import BaseModel, Field

from ..lib.engine import SUPPORTED_SCALES, UnsupportedScaleError
from ..lib.jobs import JobStatus, get_job, submit_job

app = FastAPI(
    title="Upscaler",
    description=(
        "Real-ESRGAN image upscaling server. Submit an image via "
        "POST /v1/upscale, then poll GET /v1/upscale/{job_id} until the job "
        "completes, and fetch the result from GET /v1/upscale/{job_id}/result.\n\n"
        "Example (matches tests/fixtures/sample.png used in scripts/test_upscaler_http.sh):\n"
        "```bash\n"
        "curl -F \"file=@upscaler/tests/fixtures/sample.png\" -F \"scale=4\" "
        "http://localhost:8080/v1/upscale\n"
        "```"
    ),
)

MODEL_READY = False


# ---------- Response Models ----------

class StatusResponse(BaseModel):
    model_loaded: bool = Field(..., example=True)


class JobSubmittedResponse(BaseModel):
    job_id: str = Field(..., example="8f14e45f-ceea-4e94-b4c3-8ddd9e2b0e18")
    status: JobStatus = Field(..., example=JobStatus.PENDING)


class JobStatusResponse(BaseModel):
    job_id: str = Field(..., example="8f14e45f-ceea-4e94-b4c3-8ddd9e2b0e18")
    status: JobStatus = Field(..., example=JobStatus.COMPLETED)
    progress: float = Field(..., example=1.0)
    error: Optional[str] = Field(None, example=None)


# ---------- Startup ----------

@app.on_event("startup")
async def startup_event():
    global MODEL_READY
    MODEL_READY = True


# ---------- Status ----------

@app.get(
    "/status",
    response_model=StatusResponse,
    responses={200: {"content": {"application/json": {"example": {"model_loaded": True}}}}},
)
async def status():
    return {"model_loaded": MODEL_READY}


# ---------- Submit a job ----------

@app.post(
    "/v1/upscale",
    response_model=JobSubmittedResponse,
    status_code=202,
    summary="Upload an image and start an upscale job",
    description=(
        "Uploads an image and starts an async upscale job, returning a job_id "
        "to poll. Example:\n\n"
        "```bash\n"
        "curl -F \"file=@upscaler/tests/fixtures/sample.png\" -F \"scale=4\" "
        "http://localhost:8080/v1/upscale\n"
        "```"
    ),
    responses={
        202: {
            "content": {
                "application/json": {
                    "example": {
                        "job_id": "8f14e45f-ceea-4e94-b4c3-8ddd9e2b0e18",
                        "status": "pending",
                    }
                }
            }
        },
        400: {"content": {"application/json": {"example": {"detail": "Unsupported scale: 3. Supported scales: [2, 4]"}}}},
    },
)
async def create_upscale_job(
    file: UploadFile = File(..., description="Image to upscale (PNG or JPEG)."),
    scale: int = Form(..., description="Output scale factor.", example=4),
):
    if scale not in SUPPORTED_SCALES:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported scale: {scale}. Supported scales: {sorted(SUPPORTED_SCALES)}",
        )

    image_bytes = await file.read()
    job = submit_job(image_bytes, scale)
    return {"job_id": job.id, "status": job.status}


# ---------- Poll job status ----------

@app.get(
    "/v1/upscale/{job_id}",
    response_model=JobStatusResponse,
    summary="Get upscale job status/progress",
    responses={
        200: {
            "content": {
                "application/json": {
                    "example": {
                        "job_id": "8f14e45f-ceea-4e94-b4c3-8ddd9e2b0e18",
                        "status": "completed",
                        "progress": 1.0,
                        "error": None,
                    }
                }
            }
        },
        404: {"content": {"application/json": {"example": {"detail": "Job not found"}}}},
    },
)
async def get_upscale_job(job_id: str):
    job = get_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Job not found")
    return {
        "job_id": job.id,
        "status": job.status,
        "progress": job.progress,
        "error": job.error,
    }


# ---------- Fetch job result ----------

@app.get(
    "/v1/upscale/{job_id}/result",
    summary="Download the upscaled image once the job has completed",
    responses={
        200: {"content": {"image/png": {}}},
        404: {"content": {"application/json": {"example": {"detail": "Job not found"}}}},
        409: {"content": {"application/json": {"example": {"detail": "Job is not completed yet (status=running)"}}}},
        422: {"content": {"application/json": {"example": {"detail": "Job failed: <error message>"}}}},
    },
)
async def get_upscale_job_result(job_id: str):
    job = get_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Job not found")
    if job.status == JobStatus.FAILED:
        raise HTTPException(status_code=422, detail=f"Job failed: {job.error}")
    if job.status != JobStatus.COMPLETED:
        raise HTTPException(
            status_code=409,
            detail=f"Job is not completed yet (status={job.status})",
        )
    return Response(content=job.result_path.read_bytes(), media_type="image/png")
