from contextlib import asynccontextmanager
from typing import Optional

from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel, Field

from ..lib.engine import DEFAULT_GUIDANCE_SCALE, DEFAULT_HEIGHT, DEFAULT_STEPS, DEFAULT_WIDTH, get_pipeline
from ..lib.jobs import JobStatus, get_job, get_queue_position, submit_job
from ..mcp.server import mcp as mcp_server

MODEL_READY = False


@asynccontextmanager
async def lifespan(_app: FastAPI):
    global MODEL_READY
    get_pipeline()  # slow (loads the quantized text encoder + GGUF transformer); blocks startup
    MODEL_READY = True
    async with mcp_server.session_manager.run():
        yield


app = FastAPI(
    title="txt2img",
    description=(
        "Z-Image-Turbo text-to-image server (4-bit quantized text encoder + "
        "GGUF transformer). Submit a prompt via POST /v1/generate, then "
        "poll GET /v1/generate/{job_id} until the job completes, and fetch "
        "the result from GET /v1/generate/{job_id}/result.\n\n"
        "Example (matches scripts/test_txt2img_http.sh):\n"
        "```bash\n"
        "curl -X POST http://localhost:8080/v1/generate "
        "-H \"Content-Type: application/json\" "
        "-d '{\"prompt\": \"three cute cats playing\", \"steps\": 8}'\n"
        "```\n\n"
        "Jobs are queued and run strictly one at a time (one GPU, one job "
        "in flight); GET /v1/generate/{job_id} reports queue_position "
        "(0 = running).\n\n"
        "Every generated image is checked by an NSFW safety filter "
        "(see txt2img/src/lib/safety.py) before being stored; a flagged "
        "image fails the job with error_code=content_policy_violation, and "
        "GET .../result returns 400 with that same code. Set "
        "SAFETY_CHECKER=disabled to turn this off.\n\n"
        "The same `generate_image` tool is also reachable as an MCP server "
        "over Streamable HTTP at /mcp (see txt2img/src/mcp/server.py) -- it "
        "refuses instead of queueing if a job is already in flight, and "
        "points the caller at this endpoint."
    ),
    lifespan=lifespan,
)

# Exposes the generate_image MCP tool at exactly /mcp (see the
# streamable_http_path="/" override in src/mcp/server.py).
app.mount("/mcp", mcp_server.streamable_http_app())


# ---------- Request/Response Models ----------

class GenerateRequest(BaseModel):
    prompt: str = Field(..., example="three cute cats playing")
    negative_prompt: str = Field("", example="blurry, low detail")
    steps: int = Field(DEFAULT_STEPS, example=DEFAULT_STEPS, description="Number of inference steps.")
    guidance_scale: float = Field(
        DEFAULT_GUIDANCE_SCALE,
        example=DEFAULT_GUIDANCE_SCALE,
        description="CFG scale. Z-Image-Turbo is CFG-free -- leave at 0.0 unless you know what you're doing.",
    )
    width: int = Field(DEFAULT_WIDTH, example=DEFAULT_WIDTH)
    height: int = Field(DEFAULT_HEIGHT, example=DEFAULT_HEIGHT)
    seed: Optional[int] = Field(None, example=42, description="Omit for a random seed.")


class JobSubmittedResponse(BaseModel):
    job_id: str = Field(..., example="8f14e45f-ceea-4e94-b4c3-8ddd9e2b0e18")
    status: JobStatus = Field(..., example=JobStatus.QUEUED)
    queue_position: int = Field(..., example=0, description="0 = running next; N = N jobs ahead of it.")


class JobStatusResponse(BaseModel):
    job_id: str = Field(..., example="8f14e45f-ceea-4e94-b4c3-8ddd9e2b0e18")
    status: JobStatus = Field(..., example=JobStatus.COMPLETED)
    progress: float = Field(..., example=1.0)
    queue_position: Optional[int] = Field(
        None, example=None, description="0 = running; N = N jobs ahead; null once finished."
    )
    error: Optional[str] = Field(None, example=None)
    error_code: Optional[str] = Field(
        None, example=None, description="Machine-readable reason, e.g. 'content_policy_violation'."
    )


class StatusResponse(BaseModel):
    model_loaded: bool = Field(..., example=True)


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
    "/v1/generate",
    response_model=JobSubmittedResponse,
    status_code=202,
    summary="Submit a prompt and start a generation job",
    description=(
        "Queues a generation job, returning a job_id to poll. Jobs always "
        "run one at a time -- this never rejects for capacity, it just "
        "queues behind whatever is already running. Example:\n\n"
        "```bash\n"
        "curl -X POST http://localhost:8080/v1/generate "
        "-H \"Content-Type: application/json\" "
        "-d '{\"prompt\": \"three cute cats playing\", \"steps\": 8}'\n"
        "```"
    ),
    responses={
        202: {
            "content": {
                "application/json": {
                    "example": {
                        "job_id": "8f14e45f-ceea-4e94-b4c3-8ddd9e2b0e18",
                        "status": "queued",
                        "queue_position": 0,
                    }
                }
            }
        },
    },
)
async def create_generate_job(req: GenerateRequest):
    job = submit_job(
        prompt=req.prompt,
        negative_prompt=req.negative_prompt,
        steps=req.steps,
        guidance_scale=req.guidance_scale,
        width=req.width,
        height=req.height,
        seed=req.seed,
    )
    position = get_queue_position(job.id)
    return {"job_id": job.id, "status": job.status, "queue_position": position if position is not None else 0}


# ---------- Poll job status ----------

@app.get(
    "/v1/generate/{job_id}",
    response_model=JobStatusResponse,
    summary="Get generation job status/progress",
    responses={
        200: {
            "content": {
                "application/json": {
                    "example": {
                        "job_id": "8f14e45f-ceea-4e94-b4c3-8ddd9e2b0e18",
                        "status": "completed",
                        "progress": 1.0,
                        "queue_position": None,
                        "error": None,
                        "error_code": None,
                    }
                }
            }
        },
        404: {"content": {"application/json": {"example": {"detail": "Job not found"}}}},
    },
)
async def get_generate_job(job_id: str):
    job = get_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Job not found")
    return {
        "job_id": job.id,
        "status": job.status,
        "progress": job.progress,
        "queue_position": get_queue_position(job.id),
        "error": job.error,
        "error_code": job.error_code,
    }


# ---------- Fetch job result ----------

@app.get(
    "/v1/generate/{job_id}/result",
    summary="Download the generated image once the job has completed",
    responses={
        200: {"content": {"image/png": {}}},
        400: {
            "content": {
                "application/json": {
                    "example": {
                        "detail": "Generated content was refused by the safety checker (label='nsfw', score=0.987). ...",
                        "code": "content_policy_violation",
                    }
                }
            }
        },
        404: {"content": {"application/json": {"example": {"detail": "Job not found"}}}},
        409: {"content": {"application/json": {"example": {"detail": "Job is not completed yet (status=running)"}}}},
        422: {"content": {"application/json": {"example": {"detail": "Job failed: <error message>"}}}},
    },
)
async def get_generate_job_result(job_id: str):
    job = get_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Job not found")
    if job.status == JobStatus.FAILED:
        if job.error_code == "content_policy_violation":
            raise HTTPException(
                status_code=400,
                detail={"detail": job.error, "code": job.error_code},
            )
        raise HTTPException(status_code=422, detail=f"Job failed: {job.error}")
    if job.status != JobStatus.COMPLETED:
        raise HTTPException(
            status_code=409,
            detail=f"Job is not completed yet (status={job.status})",
        )
    return Response(content=job.result_path.read_bytes(), media_type="image/png")
