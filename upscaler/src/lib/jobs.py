"""In-memory async job queue backing the HTTP upload-and-poll flow.

Only one job runs at a time: a single worker thread drains a FIFO queue, one
engine instance holds one GPU. Job/queue state lives only in this process --
if the container restarts, in-flight jobs are lost (acceptable for a
preloaded, stateless model server).
"""
import enum
import os
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

from .engine import upscale_bytes

JOB_OUTPUT_DIR = Path(os.environ.get("JOB_OUTPUT_DIR", "/app/jobs"))
JOB_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

_executor = ThreadPoolExecutor(max_workers=1)
_lock = threading.Lock()


class JobStatus(str, enum.Enum):
    QUEUED = "queued"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"


@dataclass
class Job:
    id: str
    status: JobStatus = JobStatus.QUEUED
    progress: float = 0.0
    error: Optional[str] = None
    result_path: Optional[Path] = None
    created_at: float = field(default_factory=time.time)
    updated_at: float = field(default_factory=time.time)


_jobs: dict[str, Job] = {}

# FIFO order of jobs not yet finished. _queue[0] is the job currently
# running (or about to run next); its length is the queue depth.
_queue: list[str] = []


def _update(job_id: str, **kwargs) -> None:
    with _lock:
        job = _jobs[job_id]
        for key, value in kwargs.items():
            setattr(job, key, value)
        job.updated_at = time.time()


def _run(job_id: str, image_bytes: bytes, scale: int) -> None:
    _update(job_id, status=JobStatus.RUNNING, progress=0.1)
    try:
        result_bytes = upscale_bytes(image_bytes, scale)
        result_path = JOB_OUTPUT_DIR / f"{job_id}.png"
        result_path.write_bytes(result_bytes)
        _update(job_id, status=JobStatus.COMPLETED, progress=1.0, result_path=result_path)
    except Exception as exc:  # noqa: BLE001 - reported via job.error, not raised
        _update(job_id, status=JobStatus.FAILED, progress=1.0, error=str(exc))
    finally:
        with _lock:
            _queue.remove(job_id)


def submit_job(image_bytes: bytes, scale: int) -> Job:
    """Queue a job for upscaling. Always accepted -- jobs run strictly one
    at a time, in submission order; see get_queue_position() to report where
    a job sits in that line."""
    job = Job(id=str(uuid.uuid4()))
    with _lock:
        _jobs[job.id] = job
        _queue.append(job.id)
    _executor.submit(_run, job.id, image_bytes, scale)
    return job


def get_job(job_id: str) -> Optional[Job]:
    with _lock:
        return _jobs.get(job_id)


def get_queue_position(job_id: str) -> Optional[int]:
    """0 if the job is running (or about to run next), 1+ for its place in
    line, or None if the job isn't queued (finished, or unknown id)."""
    with _lock:
        try:
            return _queue.index(job_id)
        except ValueError:
            return None


def get_active_job() -> Optional[Job]:
    """The job currently running or next in line, if any."""
    with _lock:
        if not _queue:
            return None
        return _jobs[_queue[0]]
