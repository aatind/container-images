#!/usr/bin/env bash
# Build the Qwen3.8 Flash DGX UltraFast (v16b) image, scan it with Trivy,
# and push it. Run from anywhere; paths are resolved relative to this
# script. Runs in CI (.github/workflows/qwen3-8-flash-next-ultrafast.yaml)
# or on any arm64 machine with Docker and ~50 GB free disk.
#
#   1. fetch the recipe at RECIPE_COMMIT
#   2. the recipe's recipe/build/image/build.sh --run: pulls the pinned
#      vllm/vllm-openai parent, checks every patch's hash, builds iter6c +
#      iter6d, runs the recipe's CPU test gates
#   3. ../Dockerfile on top (drafter builder + draft vocabulary)
#   4. Trivy scan, then push
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT_DIR="$(dirname "$SCRIPT_DIR")"

IMAGE_REPO="ghcr.io/aatind/qwen38-flash-dgx"
RECIPE_URL="https://github.com/dime-online/qwen3.8-Flash-DGX-UltraFast.git"
RECIPE_COMMIT="0c391a3e74b6a775cfe248691ca7fd855b1876a5"
# The recipe's image tag (recipe/build/image/build.sh) + recipe commit
IMAGE_TAG="v16b-iter6d-20260910-${RECIPE_COMMIT:0:7}"
BASE_IMAGE="qwen38-flash-dgx:iter6d-20260910"
SEVERITY="HIGH,CRITICAL"
FAIL_ON_VULNS=0
DRY_RUN=0
SKIP_SCAN=0
WORK_DIR=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

  --repo REPO           Image repo to push to (default: ${IMAGE_REPO})
  --tag TAG             Image tag (default: ${IMAGE_TAG})
  --work-dir DIR        Where to fetch the recipe (default: a new temp dir)
  --severity LIST       Trivy severities to report (default: ${SEVERITY})
  --fail-on-vulns       Don't push if Trivy finds any (default: report only)
  --dry-run             Build and scan, but don't push
  --skip-scan           Skip the Trivy scan
  -h, --help            Show this help

arm64 only: the image is for the DGX Sparks (GB10), and the recipe's
patches and tests target that build. Requires docker, git, md5sum,
sha256sum, trivy (unless --skip-scan) and a 'docker login' for the
registry.

Trivy is report-only by default, unlike the other images here: the base
is a CUDA + PyTorch + vLLM image with findings this layer can't fix
without changing what the recipe measured.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --repo) IMAGE_REPO="$2"; shift 2 ;;
        --tag) IMAGE_TAG="$2"; shift 2 ;;
        --work-dir) WORK_DIR="$2"; shift 2 ;;
        --severity) SEVERITY="$2"; shift 2 ;;
        --fail-on-vulns) FAIL_ON_VULNS=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --skip-scan) SKIP_SCAN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

for tool in docker git md5sum sha256sum; do
    command -v "$tool" >/dev/null 2>&1 || { echo "error: $tool not found in PATH" >&2; exit 1; }
done
if [ "$SKIP_SCAN" -eq 0 ]; then
    command -v trivy >/dev/null 2>&1 || {
        echo "error: trivy not found in PATH. Install it with: brew install trivy" >&2
        exit 1
    }
fi
server_arch="$(docker version --format '{{.Server.Arch}}')"
[ "$server_arch" = arm64 ] || { echo "error: docker builds for $server_arch, need arm64" >&2; exit 1; }

if [ -z "$WORK_DIR" ]; then
    WORK_DIR="$(mktemp -d)"
fi
RECIPE_DIR="${WORK_DIR}/recipe-src"
FULL_TAG="${IMAGE_REPO}:${IMAGE_TAG}"

echo "==> Fetching ${RECIPE_URL} @ ${RECIPE_COMMIT} -> ${RECIPE_DIR}"
rm -rf "$RECIPE_DIR"
git init -q "$RECIPE_DIR"
git -C "$RECIPE_DIR" fetch -q --depth 1 "$RECIPE_URL" "$RECIPE_COMMIT"
git -C "$RECIPE_DIR" checkout -q FETCH_HEAD

echo "==> Building the recipe's measured image (${BASE_IMAGE})"
bash "${RECIPE_DIR}/recipe/build/image/build.sh" --run

echo "==> Building ${FULL_TAG}"
docker build --network none --pull=false \
    --build-arg "BASE=${BASE_IMAGE}" \
    --label "org.opencontainers.image.source=https://github.com/aatind/container-images" \
    --label "org.opencontainers.image.revision=${RECIPE_COMMIT}" \
    -f "${CONTEXT_DIR}/Dockerfile" \
    -t "$FULL_TAG" \
    "$RECIPE_DIR"

if [ "$SKIP_SCAN" -eq 1 ]; then
    echo "==> Skipping Trivy scan (--skip-scan)"
else
    echo "==> Scanning ${FULL_TAG} with Trivy (severity: ${SEVERITY})"
    TRIVY_ARGS=(image --scanners vuln --severity "${SEVERITY}" --ignore-unfixed --no-progress
        --exit-code "$FAIL_ON_VULNS")
    if [ -f "${CONTEXT_DIR}/.trivyignore" ]; then
        TRIVY_ARGS+=(--ignorefile "${CONTEXT_DIR}/.trivyignore")
    fi
    if ! trivy "${TRIVY_ARGS[@]}" "$FULL_TAG"; then
        echo "==> Trivy found ${SEVERITY} vulnerabilities. Not pushing ${FULL_TAG}." >&2
        exit 1
    fi
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo "==> --dry-run set, not pushing"
    exit 0
fi

echo "==> Pushing ${FULL_TAG}"
docker push "$FULL_TAG"
docker image inspect "$FULL_TAG" --format '==> Pushed {{index .RepoDigests 0}}'
