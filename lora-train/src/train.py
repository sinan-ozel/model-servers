"""LoRA training for Z-Image Turbo on a folder of images.

Reads DATASET_DIR (images + description.yaml, see dataset.py) and writes
<output>/<trigger-word>.safetensors in diffusers LoRA format, for
ZImagePipeline.load_lora_weights().

The transformer is loaded in 4-bit NF4 (QLoRA-style) so that training fits on
12GB. Only the attention projections get LoRA layers. Captions are encoded with
the same 4-bit Qwen3 text encoder that txt2img uses, so the training
embeddings match what inference sees. Conventions follow diffusers'
ZImagePipeline: chat-template prompts, Qwen3 hidden_states[-2] trimmed by
attention mask, the (1000 - t)/1000 timestep, and a negated model output.
"""
import argparse
import os
import random
import re
import sys
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F
from diffusers import (
    AutoencoderKL,
    BitsAndBytesConfig,
    FlowMatchEulerDiscreteScheduler,
    ZImagePipeline,
    ZImageTransformer2DModel,
)
from diffusers.utils import convert_state_dict_to_diffusers
from peft import LoraConfig, get_peft_model_state_dict
from PIL import Image
from safetensors.torch import load_file
from transformers import AutoTokenizer, Qwen3Model

from dataset import DatasetError, load_captions

MODEL_CACHE_DIR = Path(os.environ.get("MODEL_CACHE_DIR", "/app/model-cache"))
BASE_MODEL_DIR = MODEL_CACHE_DIR / "hub" / "models--Tongyi-MAI--Z-Image-Turbo"
# Ostris's de-distillation training adapter (Apache-2.0): a frozen LoRA that
# keeps Turbo's step-distillation from degrading while the identity LoRA
# trains on top of it. See lora-train/README.md for why this is needed and
# https://huggingface.co/ostris/zimage_turbo_training_adapter for the source.
DISTILL_ADAPTER_PATH = MODEL_CACHE_DIR / "zimage_turbo_distill_adapter.safetensors"

# Attention projections and feed-forward layers of every transformer block.
TARGET_MODULES = ["to_q", "to_k", "to_v", "to_out.0", "w1", "w2", "w3"]
# Same prompt length cap as ZImagePipeline's default.
MAX_TEXT_TOKENS = 512


def resolve_base_path() -> Path:
    snapshots = sorted((BASE_MODEL_DIR / "snapshots").glob("*"))
    if not snapshots:
        raise FileNotFoundError(f"No Z-Image snapshot under {BASE_MODEL_DIR} -- run scripts/download_lora_train_models.sh first.")
    return snapshots[0]


def nf4_config() -> BitsAndBytesConfig:
    # Same quantization as txt2img's text encoder, so training sees the same
    # text features that inference does.
    return BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_quant_type="nf4",
        bnb_4bit_compute_dtype=torch.bfloat16,
        bnb_4bit_use_double_quant=True,
    )


def load_image(path: Path, resolution: int) -> torch.Tensor:
    """Center-crop to a square, resize, and scale to [-1, 1] as a (1, 3, H, W) tensor."""
    img = Image.open(path).convert("RGB")
    side = min(img.size)
    left, top = (img.width - side) // 2, (img.height - side) // 2
    img = img.crop((left, top, left + side, top + side)).resize((resolution, resolution), Image.Resampling.BICUBIC)
    arr = np.asarray(img, dtype=np.float32) / 127.5 - 1.0
    return torch.from_numpy(arr).permute(2, 0, 1).unsqueeze(0)


@torch.no_grad()
def build_cache(base: Path, samples, resolution: int, device: torch.device):
    """Encode every caption and image once, then free the encoder and VAE.

    Returns per-sample lists on CPU: normalized VAE latents and prompt embeddings
    (trimmed to the real token count, as the pipeline does).
    """
    tokenizer = AutoTokenizer.from_pretrained(base, subfolder="tokenizer")
    text_encoder = Qwen3Model.from_pretrained(
        base, subfolder="text_encoder", quantization_config=nf4_config(), dtype=torch.bfloat16,
    )
    vae = AutoencoderKL.from_pretrained(base, subfolder="vae", torch_dtype=torch.float32).to(device)

    prompt_embeds, latents = [], []
    for path, caption in samples:
        templated = tokenizer.apply_chat_template(
            [{"role": "user", "content": caption}],
            tokenize=False,
            add_generation_prompt=True,
            enable_thinking=True,
        )
        ids = tokenizer(
            templated, padding="max_length", max_length=MAX_TEXT_TOKENS, truncation=True, return_tensors="pt",
        )
        input_ids = ids.input_ids.to(device)
        mask = ids.attention_mask.to(device).bool()
        hidden = text_encoder(input_ids=input_ids, attention_mask=mask, output_hidden_states=True).hidden_states[-2]
        prompt_embeds.append(hidden[0][mask[0]].cpu())

        image = load_image(path, resolution).to(device, torch.float32)
        z = vae.encode(image).latent_dist.mean
        latents.append(((z - vae.config.shift_factor) * vae.config.scaling_factor).cpu())

    del text_encoder, vae
    if device.type == "cuda":
        torch.cuda.empty_cache()
    return latents, prompt_embeds


def sample_sigma(shift: float) -> float:
    """Noise level for flow matching, drawn from the same shifted schedule the scheduler uses."""
    u = random.random()
    return shift * u / (1 + (shift - 1) * u)


def train_lora(base: Path, cache, args, device: torch.device) -> ZImageTransformer2DModel:
    latents, prompt_embeds = cache
    scheduler = FlowMatchEulerDiscreteScheduler.from_pretrained(base, subfolder="scheduler")
    shift = float(scheduler.config.shift)
    transformer = ZImageTransformer2DModel.from_pretrained(
        base, subfolder="transformer", quantization_config=nf4_config(), torch_dtype=torch.bfloat16,
    )

    used_distill_helper = False
    if not args.skip_distill_helper and DISTILL_ADAPTER_PATH.exists():
        # ai-toolkit saves this with a "diffusion_model." key prefix (its
        # ComfyUI-style convention); strip it so the keys match this bare
        # model's own module tree ("layers.0.attention.to_k...").
        raw_sd = load_file(str(DISTILL_ADAPTER_PATH))
        distill_sd = {k.removeprefix("diffusion_model."): v for k, v in raw_sd.items()}
        transformer.load_lora_adapter(distill_sd, adapter_name="distill_helper", prefix=None)
        used_distill_helper = True
        print("loaded the de-distillation adapter (frozen) alongside the new identity LoRA", flush=True)
    elif not args.skip_distill_helper:
        print(
            "warning: de-distillation adapter not bundled -- training directly on Turbo, "
            "which is known to degrade its step-distillation (see lora-train/README.md)",
            file=sys.stderr,
        )

    transformer.add_adapter(LoraConfig(r=args.rank, lora_alpha=args.rank, init_lora_weights="gaussian", target_modules=TARGET_MODULES), adapter_name="identity")
    transformer.set_adapters(["identity", "distill_helper"] if used_distill_helper else ["identity"])
    # The adapter's own weights must stay frozen; only the new one trains.
    for n, p in transformer.named_parameters():
        p.requires_grad_("identity" in n and "lora" in n)
    lora_params = [p for n, p in transformer.named_parameters() if p.requires_grad]
    # Keep the trainable LoRA weights in fp32 even though the base is 4-bit.
    for p in lora_params:
        p.data = p.data.float()

    transformer.enable_gradient_checkpointing()
    transformer.train()
    optimizer = torch.optim.AdamW(lora_params, lr=args.learning_rate)

    for step in range(1, args.steps + 1):
        i = random.randrange(len(latents))
        x0 = latents[i].squeeze(0).to(device, torch.float32)  # (C, H, W)
        noise = torch.randn_like(x0)
        sigma = sample_sigma(shift)
        x_t = (1 - sigma) * x0 + sigma * noise
        # Pipeline feeds (1000 - t) / 1000 with t = 1000 * sigma, and negates the
        # model output before the scheduler step, so the model learns x0 - noise.
        model_t = torch.tensor([1 - sigma], device=device, dtype=torch.float32)
        target = (x0 - noise).float()

        with torch.autocast("cuda", dtype=torch.bfloat16):
            pred = transformer(
                [x_t.to(torch.bfloat16).unsqueeze(1)],
                model_t,
                [prompt_embeds[i].to(device, torch.bfloat16)],
                return_dict=False,
            )[0][0]
        loss = F.mse_loss(pred.squeeze(1).float(), target)

        loss.backward()
        optimizer.step()
        optimizer.zero_grad(set_to_none=True)

        if step == 1 or step % 10 == 0 or step == args.steps:
            print(f"step {step}/{args.steps} loss {loss.item():.4f}", flush=True)

    return transformer


def save_lora(transformer: ZImageTransformer2DModel, output_dir: Path, trigger_word: str) -> Path:
    # adapter_name="identity" excludes the frozen de-distillation adapter,
    # if one was loaded -- only the newly trained weights are saved.
    state = convert_state_dict_to_diffusers(get_peft_model_state_dict(transformer, adapter_name="identity"))
    # Saved in fp32, not fp16: the loader keeps the file's dtype, and inputs to the
    # feed-forward LoRA layers exceed the fp16 range, which turned every image black.
    state = {k: v.to(torch.float32) for k, v in state.items()}
    output_dir.mkdir(parents=True, exist_ok=True)
    safe_name = re.sub(r"[^A-Za-z0-9_-]", "_", trigger_word)
    ZImagePipeline.save_lora_weights(
        save_directory=str(output_dir),
        transformer_lora_layers=state,
        weight_name=f"{safe_name}.safetensors",
    )
    return output_dir / f"{safe_name}.safetensors"


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Train a Z-Image Turbo LoRA on a folder of images.")
    p.add_argument("dataset_dir", type=Path, help="folder with images and description.yaml")
    p.add_argument("--trigger-word", default="img", help="token that binds the subject (default: img)")
    p.add_argument("--output", type=Path, default=None, help="output folder (default: <dataset_dir>/output)")
    p.add_argument("--steps", type=int, default=1000)
    p.add_argument("--rank", type=int, default=16)
    p.add_argument("--learning-rate", type=float, default=1e-4)
    p.add_argument("--resolution", type=int, default=1024, help="square training resolution, multiple of 64")
    p.add_argument("--seed", type=int, default=0)
    p.add_argument(
        "--skip-distill-helper", action="store_true",
        help="train directly on Turbo instead of loading the bundled de-distillation adapter "
             "(not recommended -- see lora-train/README.md)",
    )
    return p.parse_args()


def main() -> int:
    args = parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_-]+", args.trigger_word):
        print("error: --trigger-word may contain only letters, digits, '_' and '-'", file=sys.stderr)
        return 2
    if args.steps < 1 or args.rank < 1 or args.resolution < 256 or args.resolution % 64:
        print("error: need steps >= 1, rank >= 1, and resolution >= 256 that is a multiple of 64", file=sys.stderr)
        return 2
    if not torch.cuda.is_available():
        print("error: CUDA is required for training (run with --gpus all)", file=sys.stderr)
        return 2

    try:
        samples = load_captions(args.dataset_dir, args.trigger_word)
    except DatasetError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2

    random.seed(args.seed)
    torch.manual_seed(args.seed)
    device = torch.device("cuda")
    base = resolve_base_path()
    output_dir = args.output or (args.dataset_dir / "output")

    print(f"{len(samples)} images, trigger word '{args.trigger_word}', {args.steps} steps", flush=True)
    cache = build_cache(base, samples, args.resolution, device)
    transformer = train_lora(base, cache, args, device)
    path = save_lora(transformer, output_dir, args.trigger_word)
    print(f"saved {path}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
