# Vendored from TencentARC/PhotoMaker

Source: https://github.com/TencentARC/PhotoMaker
Pinned commit: `060b4fcb10b76a4554edf565d6106b7e36c968f0` (2024-10-31)
License: Apache License 2.0 (see upstream repo's `LICENSE`)

Files vendored from `photomaker/`:
- `model.py` -- `PhotoMakerIDEncoder` (PhotoMaker V1, `CLIPVisionModelWithProjection`-based, no insightface/ArcFace anywhere). Unmodified.
- `model_v2.py` -- `PhotoMakerIDEncoder_CLIPInsightfaceExtendtoken` (PhotoMaker V2). Vendored only because `pipeline.py` imports this name from the package `__init__.py` at module load time; **never instantiated at runtime** by this pipeline, which always calls `load_photomaker_adapter(..., pm_version="v1")`. Verified directly: this file itself has zero `insightface` imports -- it just accepts an externally-computed `id_embeds` tensor as an optional forward() argument, which this pipeline never provides. Unmodified.
- `pipeline.py` -- `PhotoMakerStableDiffusionXLPipeline`. **Modified**, two fixes:
  1. `load_photomaker_adapter()` called `_get_model_file(..., resume_download=...)`, a `huggingface_hub` kwarg removed in newer releases (this pipeline uses `huggingface_hub==0.36.2`, well past PhotoMaker's Oct 2024 pin). Dropped `resume_download` from the call entirely rather than pinning an older `huggingface_hub` that might conflict with `diffusers==0.38.0`'s own requirements. No behavioral change for offline, fully-bundled use (this pipeline never resumes a partial download at runtime anyway -- all weights are baked in at build time).
  2. `load_photomaker_adapter()` hardcoded `self.num_tokens = 2` unconditionally. This is correct for V2 (its resampler-based encoder produces 2 tokens per ID image) but wrong for V1: `model.py`'s `PhotoMakerIDEncoder.forward()` produces exactly 1 token per image (`id_embeds.view(b, num_inputs, 1, -1)`). With the upstream hardcoded value, `encode_prompt_with_trigger_word()` expands the trigger token into `num_id_images * 2` mask positions, but `FuseModule.forward()` only receives `num_id_images * 1` actual image embeddings -- a shape mismatch (`RuntimeError: Sizes of tensors must match ... Expected size 2 but got size 1`) that reproduces on every `pm_version="v1"` call, not something specific to this pipeline's quantization setup. Fixed with `self.num_tokens = 2 if pm_version == "v2" else 1`. This looks like a genuine latent bug in upstream PhotoMaker's V1 path at this pinned commit -- worth reporting upstream.
  3. Two `print()` calls (in `load_photomaker_adapter()` and the tokenizer-truncation-warning branch of `encode_prompt_with_trigger_word()`) wrote to stdout. This corrupts the MCP stdio transport, which uses stdout exclusively for JSON-RPC messages -- any stray print() breaks the protocol stream. The Python `mcp` SDK client tolerated it in testing (it logs a parse error and skips the malformed line rather than failing outright), but a stricter client could fail. Redirected both to stderr (`file=sys.stderr`). `model_v2.py` has one more (`print(cross_attention_dim*num_tokens)` in `MLPProjModel.__init__`) but it's unreachable here since V2 is never instantiated -- left as-is.
- `resampler.py` -- `FacePerceiverResampler` (used by `model_v2.py`; not reachable at runtime here either, but required for `model_v2.py` to import). Unmodified.

Deliberately **not** vendored: `insightface_package.py` (the only file in
upstream that imports the `insightface` pip package), `model_v2.py`'s
pipeline usage path, `pipeline_controlnet.py`, `pipeline_t2i_adapter.py`,
`gradio_demo/`, `inference_scripts/`. This pipeline's own `__init__.py`
(not copied from upstream) imports only what's needed and never imports
`insightface_package`.

Why this matters: insightface's *pretrained model weights* (not its code)
are licensed non-commercial-research-only. PhotoMaker V1 has no dependency
on insightface at all; V2 does (via a separately-computed ArcFace
embedding). This project uses V1 specifically to avoid that restriction --
see `faceid/README.md`'s Credits section.
