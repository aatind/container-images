#!/usr/bin/env bash
# Build the ops-toolbox image with apko, scan each platform with Trivy, and
# push a multi-arch manifest to Docker Hub only if every platform is clean.
# Run from anywhere; paths are resolved relative to this script.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG="${CONTEXT_DIR}/apko.yaml"

IMAGE_REPO="aatind/ops-toolbox"
TAG="$(date +%Y%m%d)"
SEVERITY="HIGH,CRITICAL"
IGNORE_UNFIXED=1
PUSH_LATEST=1
DRY_RUN=0
SKIP_SCAN=0
PLATFORMS="x86_64,aarch64"

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

  --tag TAG             Image tag (default: today's date, ${TAG})
  --repo REPO           Docker Hub repo to push to (default: ${IMAGE_REPO})
  --platforms LIST      Comma-separated apko archs (default: ${PLATFORMS})
  --severity LIST       Trivy severities that fail the scan (default: ${SEVERITY})
  --include-unfixed     Fail on vulns even if no fix is available yet (default: ignored)
  --no-latest           Don't also tag/push :latest
  --dry-run             Build and scan every platform, but don't push
  --skip-scan           Skip the Trivy scan (not recommended)
  -h, --help            Show this help

Requires: apko (brew install apko), docker, trivy (brew install trivy), and
an authenticated 'docker login' session for pushes.

apko has no notion of an "upstream version" (Wolfi is rolling-release, so
the same apko.yaml can resolve to different package versions on different
days) so images are tagged by build date, not by an upstream version
number the way nextcloud-w-smb is. Reference the dated tag from gitops,
not :latest, so deployments stay reproducible.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --tag) TAG="$2"; shift 2 ;;
        --repo) IMAGE_REPO="$2"; shift 2 ;;
        --platforms) PLATFORMS="$2"; shift 2 ;;
        --severity) SEVERITY="$2"; shift 2 ;;
        --include-unfixed) IGNORE_UNFIXED=0; shift ;;
        --no-latest) PUSH_LATEST=0; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --skip-scan) SKIP_SCAN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

command -v apko >/dev/null 2>&1 || { echo "error: apko not found in PATH. Install it with: brew install apko" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "error: docker not found in PATH" >&2; exit 1; }
if [ "$SKIP_SCAN" -eq 0 ]; then
    command -v trivy >/dev/null 2>&1 || {
        echo "error: trivy not found in PATH. Install it with: brew install trivy" >&2
        exit 1
    }
fi

VERSION_TAG="${IMAGE_REPO}:${TAG}"
LATEST_TAG="${IMAGE_REPO}:latest"

# apko names the tag it loads into docker as "<tag>-<docker-arch>" (docker's
# amd64/arm64 naming, not apko's own x86_64/aarch64 arch names)
docker_arch_suffix() {
    case "$1" in
        x86_64) echo "amd64" ;;
        aarch64) echo "arm64" ;;
        *) echo "$1" ;;
    esac
}

IFS=',' read -r -a PLATFORM_ARR <<< "$PLATFORMS"

for platform in "${PLATFORM_ARR[@]}"; do
    tarfile="$(mktemp -d)/image.tar"

    echo "==> Building ${platform} (config: ${CONFIG})"
    apko build "$CONFIG" "$VERSION_TAG" "$tarfile" --arch "$platform"

    echo "==> Loading ${platform} image into docker"
    docker load < "$tarfile"
    platform_tag="${VERSION_TAG}-$(docker_arch_suffix "$platform")"

    if [ "$SKIP_SCAN" -eq 1 ]; then
        echo "==> Skipping Trivy scan (--skip-scan)"
        continue
    fi

    echo "==> Scanning ${platform_tag} with Trivy (severity: ${SEVERITY})"
    TRIVY_ARGS=(image --severity "${SEVERITY}" --exit-code 1 --no-progress)
    if [ "$IGNORE_UNFIXED" -eq 1 ]; then
        TRIVY_ARGS+=(--ignore-unfixed)
    fi
    if [ -f "${CONTEXT_DIR}/.trivyignore" ]; then
        TRIVY_ARGS+=(--ignorefile "${CONTEXT_DIR}/.trivyignore")
    fi
    if ! trivy "${TRIVY_ARGS[@]}" "${platform_tag}"; then
        echo "==> Trivy found ${SEVERITY} vulnerabilities in ${platform}. Not pushing ${VERSION_TAG}." >&2
        exit 1
    fi
    echo "==> ${platform} scan clean"
done

if [ "$DRY_RUN" -eq 1 ]; then
    echo "==> --dry-run set, not pushing"
    exit 0
fi

PUBLISH_TAGS=("$VERSION_TAG")
if [ "$PUSH_LATEST" -eq 1 ]; then
    PUBLISH_TAGS+=("$LATEST_TAG")
fi

echo "==> Building and publishing multi-arch manifest for ${PLATFORMS}"
apko publish "$CONFIG" "${PUBLISH_TAGS[@]}" --arch "$PLATFORMS"

echo "==> Done"
