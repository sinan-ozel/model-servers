"""Vendored subset of TencentARC/PhotoMaker (Apache-2.0) -- see NOTICE.md.

Deliberately does NOT import the upstream package's own __init__.py, which
pulls in insightface_package.py (requires the `insightface` pip package).
This pipeline only uses PhotoMaker V1 (pm_version="v1" when calling
load_photomaker_adapter), which never touches insightface -- see NOTICE.md
for why.

model_v2.py IS vendored (it has zero insightface imports itself -- verified
directly) solely because pipeline.py does `from . import (PhotoMakerIDEncoder,
PhotoMakerIDEncoder_CLIPInsightfaceExtendtoken)` at module load time
regardless of which pm_version is ever actually used at runtime. Both names
must be bound here, in this order, before `.pipeline` is imported below.
"""
from .model import PhotoMakerIDEncoder
from .model_v2 import PhotoMakerIDEncoder_CLIPInsightfaceExtendtoken
from .pipeline import PhotoMakerStableDiffusionXLPipeline

__all__ = [
    "PhotoMakerIDEncoder",
    "PhotoMakerIDEncoder_CLIPInsightfaceExtendtoken",
    "PhotoMakerStableDiffusionXLPipeline",
]
