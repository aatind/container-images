# qwen3-8-flash-next-ultrafast

vLLM for Qwen3.8-Flash-Next on one NVIDIA DGX Spark (GB10), built from the
[Qwen3.8 Flash DGX UltraFast](https://github.com/dime-online/qwen3.8-Flash-DGX-UltraFast)
recipe, v16b (Apache-2.0). Used by `qwen3-8-flash-next` in
[cebra-ai-inference](https://github.com/aatind/cebra-ai-inference).

Published on Docker Hub as
[`aatind/qwen38-flash-dgx:v16b-iter6d-20260910-0c391a3`](https://hub.docker.com/r/aatind/qwen38-flash-dgx)
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
- **Single-arch, plain `docker build`/`docker push`** (no buildx manifest):
  the recipe's own `build.sh` builds with the local Docker engine. Build it
  on an arm64 machine with ~50 GB free disk, e.g. an Apple Silicon Mac.
- **Trivy reports, doesn't block** (`--fail-on-vulns` to block). The base is
  a CUDA + PyTorch + vLLM image whose findings can't be fixed here without
  changing what the recipe measured.
  The script runs a pinned Linux Trivy inside the built image
  (`trivy rootfs /`) instead of `trivy image`, which copies the whole
  ~25 GB image to local disk first; no local Trivy install needed.

## Build, scan, and publish

On an arm64 machine (Docker Desktop: give its VM at least 10 GB of memory;
the recipe's tests run in 8 GB containers):

```sh
brew install coreutils bash   # one-time; the recipe needs GNU md5sum/sha256sum and bash >= 4.4
docker login         # one-time, needs push access to aatind/qwen38-flash-dgx
scripts/build-and-push.sh --dry-run
scripts/build-and-push.sh
```

The Docker Hub repo must stay public: the DGX Sparks pull it without
credentials.

Run `scripts/build-and-push.sh --help` for all flags.

## Bumping the recipe

1. Pick the new commit of the recipe and read its changelog: a new
   commit can change the launch flags as well as the image.
2. Set `RECIPE_COMMIT` (and `BASE_IMAGE` and the tag prefix in `IMAGE_TAG`
   if the recipe's `build.sh` tags changed) in `scripts/build-and-push.sh`.
3. Build and push, then update the image tag and any changed v16b flags
   in cebra-ai-inference's `qwen3-8-flash-next/deployment.yaml` together.

Renovate is turned off for this directory: everything is pinned by the
recipe commit.
