# qwen3-8-flash-next-ultrafast

vLLM for Qwen3.8-Flash-Next on one NVIDIA DGX Spark (GB10), built from the
[Qwen3.8 Flash DGX UltraFast](https://github.com/dime-online/qwen3.8-Flash-DGX-UltraFast)
recipe, v16b (Apache-2.0). Used by `qwen3-8-flash-next` in
[cebra-ai-inference](https://github.com/aatind/cebra-ai-inference).

Published as `ghcr.io/aatind/qwen38-flash-dgx:v16b-iter6d-20260910-0c391a3`
(the recipe's image tag plus the recipe commit). arm64 only.

## What it is

1. **The recipe's measured image, unchanged.** `scripts/build-and-push.sh`
   fetches the recipe at a pinned commit and runs its own
   `recipe/build/image/build.sh --run`: it pulls the pinned
   `vllm/vllm-openai:qwen38-flash-next` parent by digest, checks every
   patch's hash, builds the `iter6c` and `iter6d` layers and runs the
   recipe's CPU test gates.
2. **This directory's `Dockerfile` on top**, which only adds files:
   - `/opt/ultrafast/build-model/`: the recipe's drafter builder. The
     cebra-ai-inference Deployment runs it in an init container to build the
     dense-MTP drafter on the model PVC, where the recipe runs it with
     `docker run`.
   - `/opt/ultrafast/draft-vocab-ids-K65536.txt`: the MTP draft vocabulary,
     unpacked. The recipe's `launch.sh` does this on the host.
   - the recipe's `LICENSE` and `NOTICE`.

The model weights are not in the image. The Deployment downloads them.

## Differences from the other images here

- **arm64 only.** It's for the Sparks, and the recipe's patches target GB10.
- **Built in CI**, by `.github/workflows/qwen3-8-flash-next-ultrafast.yaml`
  (manual), because the build needs an arm64 machine with ~50 GB free disk.
  The script also runs on any arm64 machine with Docker, such as an Apple
  Silicon Mac with enough free disk.
- **Trivy reports, doesn't block** (`--fail-on-vulns` to block). The base is
  a CUDA + PyTorch + vLLM image whose findings can't be fixed here without
  changing what the recipe measured.
- **Pushed to GHCR**, not Docker Hub: the workflow pushes with its own
  `GITHUB_TOKEN`, so no registry secret is needed.

## Build, scan, and publish

In CI: **Actions → qwen3-8-flash-next-ultrafast → Run workflow** (tick
"dry run" to build and scan without pushing). After the first push, open
the package's settings and make it **public** if it isn't, so the Sparks
can pull it without credentials.

Locally, on arm64:

```sh
brew install trivy                 # one-time
docker login ghcr.io -u <user>     # token with write:packages
scripts/build-and-push.sh --dry-run
scripts/build-and-push.sh
```

Run `scripts/build-and-push.sh --help` for all flags.

## Bumping the recipe

1. Pick the new commit of the recipe and read its changelog: a new
   commit can change the launch flags as well as the image.
2. Set `RECIPE_COMMIT` (and `BASE_IMAGE` and the tag prefix in `IMAGE_TAG`
   if the recipe's `build.sh` tags changed) in `scripts/build-and-push.sh`.
3. Run the workflow, then update the image tag and any changed v16b flags
   in cebra-ai-inference's `qwen3-8-flash-next/deployment.yaml` together.

Renovate is turned off for this directory: everything is pinned by the
recipe commit.
