#!/usr/bin/env bash
# Build the Qwen3.8 Flash DGX UltraFast (v16b) image, scan it with Trivy,
# and push it. Run from anywhere; paths are resolved relative to this
# script. Needs an arm64 machine (e.g. an Apple Silicon Mac) with Docker
# and ~50 GB free disk.
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

IMAGE_REPO="aatind/qwen38-flash-dgx"
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
# Trivy runs inside the built image (see the scan step); pinned Linux arm64
# release + its SHA-256 from the release's trivy_<version>_checksums.txt.
# Old releases get removed from GitHub: if the download 404s, pin a newer one.
TRIVY_VERSION="0.76.0"
TRIVY_SHA256="aab21e677a7b7071fc79f1711480840754c18a1b9d9cefa7ccd06af63a0e8f4c"

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

  --repo REPO           Docker Hub repo to push to (default: ${IMAGE_REPO})
  --tag TAG             Image tag (default: ${IMAGE_TAG})
  --work-dir DIR        Where to fetch the recipe (default: a new temp dir)
  --severity LIST       Trivy severities to report (default: ${SEVERITY})
  --fail-on-vulns       Don't push if Trivy finds any (default: report only)
  --dry-run             Build and scan, but don't push
  --skip-scan           Skip the Trivy scan
  -h, --help            Show this help

arm64 only: the image is for the DGX Sparks (GB10), and the recipe's
patches and tests target that build. Requires docker, git, curl, md5sum,
sha256sum and an authenticated 'docker login' session.

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

# The recipe's build.sh needs GNU md5sum/sha256sum (--check --status from
# stdin) and bash >= 4.4 (empty arrays under set -u); macOS ships BSD-style
# checksum tools and bash 3.2, which fail its hash checks and test loop.
RECIPE_BASH=bash
if [ "$(uname -s)" = Darwin ]; then
    BREW_PREFIX=""
    command -v brew >/dev/null 2>&1 && BREW_PREFIX="$(brew --prefix)"
    GNUBIN="${BREW_PREFIX}/opt/coreutils/libexec/gnubin"
    [ -n "$BREW_PREFIX" ] && [ -x "${GNUBIN}/md5sum" ] && [ -x "${BREW_PREFIX}/bin/bash" ] || {
        echo "error: GNU coreutils or bash not found. Install them with: brew install coreutils bash" >&2
        exit 1
    }
    export PATH="${GNUBIN}:${PATH}"
    RECIPE_BASH="${BREW_PREFIX}/bin/bash"
fi

for tool in docker git curl md5sum sha256sum; do
    command -v "$tool" >/dev/null 2>&1 || { echo "error: $tool not found in PATH" >&2; exit 1; }
done
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
"$RECIPE_BASH" "${RECIPE_DIR}/recipe/build/image/build.sh" --run

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
    # `trivy image` copies the whole ~25 GB image to a temp dir first (that
    # filled the disk on a Mac). Instead run Trivy inside a container of the
    # image and scan its filesystem in place (`trivy rootfs /`).
    TRIVY_DIR="${WORK_DIR}/trivy-${TRIVY_VERSION}"
    if [ ! -x "${TRIVY_DIR}/trivy" ]; then
        echo "==> Fetching Trivy ${TRIVY_VERSION} (linux arm64)"
        mkdir -p "$TRIVY_DIR"
        tarball="${TRIVY_DIR}/trivy.tar.gz"
        curl -fsSL -o "$tarball" \
            "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-ARM64.tar.gz"
        echo "${TRIVY_SHA256}  ${tarball}" | sha256sum --check --status || {
            echo "error: Trivy download doesn't match its pinned SHA-256" >&2; exit 1;
        }
        tar -xzf "$tarball" -C "$TRIVY_DIR" trivy
        rm "$tarball"
    fi
    mkdir -p "${WORK_DIR}/trivy-cache"

    echo "==> Scanning ${FULL_TAG} with Trivy (severity: ${SEVERITY})"
    SCAN_MOUNTS=(-v "${TRIVY_DIR}:/opt/scan-trivy:ro" -v "${WORK_DIR}/trivy-cache:/scan-cache")
    # --timeout: the default 5m isn't enough for a CUDA/PyTorch image
    TRIVY_ARGS=(rootfs --cache-dir /scan-cache --scanners vuln --severity "${SEVERITY}"
        --ignore-unfixed --no-progress --timeout 60m --exit-code "$FAIL_ON_VULNS"
        --skip-dirs /proc --skip-dirs /sys --skip-dirs /dev
        --skip-dirs /opt/scan-trivy --skip-dirs /scan-cache)
    if [ -f "${CONTEXT_DIR}/.trivyignore" ]; then
        SCAN_MOUNTS+=(-v "${CONTEXT_DIR}/.trivyignore:/scan-trivyignore:ro")
        TRIVY_ARGS+=(--ignorefile /scan-trivyignore)
    fi
    if ! docker run --rm --entrypoint /opt/scan-trivy/trivy "${SCAN_MOUNTS[@]}" \
            "$FULL_TAG" "${TRIVY_ARGS[@]}" /; then
        if [ "$FAIL_ON_VULNS" -eq 1 ]; then
            echo "==> Trivy found ${SEVERITY} vulnerabilities or failed to scan. Not pushing ${FULL_TAG}." >&2
        else
            echo "==> Trivy failed to scan (see above). Not pushing ${FULL_TAG}." >&2
        fi
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
