# lora-train

A batch LoRA trainer for Z-Image Turbo. It takes a folder of images for one
subject, plus a YAML caption file, and writes a LoRA `.safetensors` file in
diffusers format, for `ZImagePipeline.load_lora_weights()`.

This is a one-shot job, not a server: it runs, writes the LoRA, and exits.

## Dataset folder

```
my_person/
  description.yaml
  front.jpg
  side.png
  smiling.webp
  ...
```

`description.yaml`:

```yaml
description: "a photo of img man, soft studio light"   # used for every image
captions:                                               # optional per-image overrides
  front.jpg: "close-up portrait of img man, neutral expression"
  smiling.webp: "img man smiling, indoors, warm light"
```

- Use 15–30 images that vary in pose, lighting, and framing. One image
  memorizes that image, not the person.
- Every image needs a caption, either from `description` or a `captions` entry.
- The trigger word is added to any caption that lacks it.
- Images are center-cropped to a square, then resized to `--resolution`.

## Train

```bash
./scripts/download_lora_train_models.sh   # ~25GB; text encoder copied from txt2img/model-cache if present
./scripts/build_lora_train.sh             # image is ~35GB
docker run --rm --gpus all --user "$(id -u):$(id -g)" -v "$PWD/my_person:/data" \
  model-servers/lora-train:zimage-cuda /data --trigger-word img --steps 1000
```

Output lands in `my_person/output/img.safetensors`.

| Flag | Default | Notes |
|---|---|---|
| `--trigger-word` | `img` | A rare token that binds the subject. Letters, digits, `_`, `-` only. |
| `--steps` | `1000` | Batch size 1. About 11s per step at 1024 on a 12GB card (measured). |
| `--rank` | `16` | LoRA rank. |
| `--learning-rate` | `1e-4` | AdamW, constant schedule. |
| `--resolution` | `1024` | Multiple of 64. 512 is much faster, but trains a different scale. |
| `--output` | `<dataset>/output` | Output folder. |
| `--skip-distill-helper` | off | Train directly on Turbo instead of loading the bundled de-distillation adapter. Not recommended; see below. |

Exit code 2 means bad input (missing `description.yaml`, a caption that refers
to a missing image, an invalid flag). It's checked before the model loads.

## Test

```bash
./scripts/test_lora_train.sh        # 20-step smoke test + missing-YAML rejection
./scripts/test_lora_train.sh 200    # longer run
```

The smoke test checks plumbing: the LoRA file is written, and bad input is
rejected. It does not check identity fidelity.

## How it trains

- The transformer is loaded in 4-bit NF4 with bitsandbytes, a QLoRA-style
  setup. The bf16 base doesn't fit in 12GB during training.
- **De-distillation adapter.** Z-Image Turbo is a step-distilled model.
  Training a LoRA directly on it degrades that distillation unpredictably,
  which showed up here as a trained LoRA with very weak identity likeness,
  confirmed against multiple independent reports of the same failure mode.
  By default, `ostris/zimage_turbo_training_adapter` (Apache-2.0) is loaded
  as a second, frozen LoRA alongside the new one. It keeps the distillation
  stable while the new LoRA learns the subject. It's excluded from the saved
  file and is not needed at inference. `--skip-distill-helper` trains without
  it, for comparison, or if long runs cause the adapter itself to show
  instability (the upstream README's own caveat). See
  [the adapter's model card](https://huggingface.co/ostris/zimage_turbo_training_adapter)
  and [a write-up of why this is needed](https://lilting.ch/en/articles/z-image-turbo-lora-dedistill-adapter).
- LoRA layers go on the attention projections (`to_q`, `to_k`, `to_v`,
  `to_out.0`) and the feed-forward layers (`w1`, `w2`, `w3`) of every block.
  The weights are trained and saved in fp32. Saving them in fp16 turned every
  generated image black: the loader keeps the file's dtype, and inputs to the
  feed-forward LoRA layers exceed the fp16 range.
- Captions are encoded with the same 4-bit Qwen3 text encoder that `txt2img`
  uses, with the pipeline's chat template, so training sees the same text
  features as inference.
- Loss is flow matching: the model predicts `x0 - noise` on the scheduler's
  shifted noise schedule, using the conventions of diffusers' `ZImagePipeline`.
- Peak VRAM was under 6GB at 1024×1024 with both adapters loaded (measured).

## Model and license

- `Tongyi-MAI/Z-Image-Turbo` (Apache-2.0). The bundled copy is the bf16
  transformer, VAE, scheduler, Qwen3 text encoder, and tokenizer.
- `ostris/zimage_turbo_training_adapter` (Apache-2.0), used only during
  training.

## Verified

- Overfit test: 300 steps on one photo at 512px, then generation with the
  exact training caption in `lora-gen` (the Q4 GGUF transformer). The output
  reproduces the person in the photo; the base model with the same prompt and
  seed produces someone unrelated. So the training loop does learn a subject.

## Not yet verified

- Likeness on a real multi-photo dataset with these settings, and how well
  it generalizes to prompts that differ from the training captions.
- Time per step at 1024px with the feed-forward layers included. At 512px it
  was about 3s per step.
