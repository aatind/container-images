#!/usr/bin/env bash
# Build the vaultwarden-hardened image, scan it with Trivy, and push it to
# Docker Hub only if the scan is clean. Run from anywhere; paths are
# resolved relative to this script.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT_DIR="$(dirname "$SCRIPT_DIR")"

IMAGE_REPO="aatind/vaultwarden"
VAULTWARDEN_VERSION="1.37.1"
SEVERITY="HIGH,CRITICAL"
IGNORE_UNFIXED=1
PUSH_LATEST=1
DRY_RUN=0
SKIP_SCAN=0
PLATFORMS="linux/amd64,linux/arm64"

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

  --version VERSION     Vaultwarden version to build (default: ${VAULTWARDEN_VERSION})
  --repo REPO           Docker Hub repo to push to (default: ${IMAGE_REPO})
  --platforms LIST      Comma-separated buildx platforms (default: ${PLATFORMS})
  --severity LIST       Trivy severities that fail the scan (default: ${SEVERITY})
  --include-unfixed     Fail on vulns even if no fix is available yet (default: ignored)
  --no-latest           Don't also tag/push :latest
  --dry-run             Build and scan every platform, but don't push
  --skip-scan           Skip the Trivy scan (not recommended)
  -h, --help            Show this help

Requires: docker with buildx (a docker-container driver builder for the
final multi-arch push — the default "docker" driver can build/load but
can't push a manifest list; see the project README), trivy
(brew install trivy), and an authenticated 'docker login' session.

Each platform is built and loaded locally so Trivy can scan it before
anything is pushed, then (if every platform passes) the real multi-arch
manifest is built and pushed in one buildx invocation using the same
build cache, so that step is fast.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --version) VAULTWARDEN_VERSION="$2"; shift 2 ;;
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

command -v docker >/dev/null 2>&1 || { echo "error: docker not found in PATH" >&2; exit 1; }
if [ "$SKIP_SCAN" -eq 0 ]; then
    command -v trivy >/dev/null 2>&1 || {
        echo "error: trivy not found in PATH. Install it with: brew install trivy" >&2
        exit 1
    }
fi

VERSION_TAG="${IMAGE_REPO}:${VAULTWARDEN_VERSION}"
LATEST_TAG="${IMAGE_REPO}:latest"

IFS=',' read -r -a PLATFORM_ARR <<< "$PLATFORMS"

for platform in "${PLATFORM_ARR[@]}"; do
    platform_tag="${VERSION_TAG}-${platform//\//-}"

    echo "==> Building ${platform} -> ${platform_tag} (context: ${CONTEXT_DIR})"
    docker buildx build \
        --platform "${platform}" \
        --build-arg "VAULTWARDEN_VERSION=${VAULTWARDEN_VERSION}" \
        -t "${platform_tag}" \
        --load \
        "${CONTEXT_DIR}"

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

BUILD_TAGS=(-t "${VERSION_TAG}")
if [ "$PUSH_LATEST" -eq 1 ]; then
    BUILD_TAGS+=(-t "${LATEST_TAG}")
fi

echo "==> Building and pushing multi-arch manifest for ${PLATFORMS}"
docker buildx build \
    --platform "${PLATFORMS}" \
    --build-arg "VAULTWARDEN_VERSION=${VAULTWARDEN_VERSION}" \
    "${BUILD_TAGS[@]}" \
    --push \
    "${CONTEXT_DIR}"

echo "==> Done"
