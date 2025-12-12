import os
import torch

try:
    with open('/app/PIPELINE.txt', 'r') as f:
        pipeline_class_name = f.read().strip()
except:
    pipeline_class_name = 'StableDiffusionPipeline'

if pipeline_class_name == 'StableDiffusionPipeline':
    from diffusers import StableDiffusionPipeline as Pipeline


# Not configurable – set at build time by prepare_model.sh
# WITHIN_CONTAINER_PATH = "/app/models/stable-diffusion-v1-4/snapshot"
with open('/app/MODEL_PATH.txt', 'r') as f:
    model_path = f.read().strip()

OVERRIDE_SAFETY_CHECKER = os.getenv('OVERRIDE_SAFETY_CHECKER', 'false').lower() == 'true'
ENABLE_CPU_OFFLOADING = os.getenv('ENABLE_CPU_OFFLOADING', 'false').lower() == 'true'

def load_model():
    if not os.path.exists(model_path):
        raise RuntimeError("Model files missing. Container incorrectly built.")

    if OVERRIDE_SAFETY_CHECKER:
        pipe = StableDPipelineiffusionPipeline.from_pretrained(
            model_path,
            torch_dtype=torch.float16,
            safety_checker=None
        )
    else:
        pipe = Pipeline.from_pretrained(
            model_path,
            torch_dtype=torch.float16
        )
    if ENABLE_CPU_OFFLOADING:
        pipe.enable_sequential_cpu_offload()
        pipe.enable_attention_slicing()
    else:
        pipe = pipe.to("cuda")
    return pipe
