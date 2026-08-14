#!/usr/bin/env bash
# Build the nextcloud-w-smb image, scan it with Trivy, and push it to Docker
# Hub only if the scan is clean. Run from anywhere; paths are resolved
# relative to this script.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT_DIR="$(dirname "$SCRIPT_DIR")"

IMAGE_REPO="aatind/nextcloud"
NEXTCLOUD_VERSION="34.0.2"
SEVERITY="HIGH,CRITICAL"
IGNORE_UNFIXED=1
PUSH_LATEST=1
DRY_RUN=0
SKIP_SCAN=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

  --version VERSION     Nextcloud version to build (default: ${NEXTCLOUD_VERSION})
  --repo REPO           Docker Hub repo to push to (default: ${IMAGE_REPO})
  --severity LIST       Trivy severities that fail the scan (default: ${SEVERITY})
  --include-unfixed     Fail on vulns even if no fix is available yet (default: ignored)
  --no-latest           Don't also tag/push :latest
  --dry-run             Build and scan, but don't push
  --skip-scan           Skip the Trivy scan (not recommended)
  -h, --help            Show this help

Requires: docker, trivy (brew install trivy), and an authenticated
'docker login' session for pushes.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --version) NEXTCLOUD_VERSION="$2"; shift 2 ;;
        --repo) IMAGE_REPO="$2"; shift 2 ;;
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

VERSION_TAG="${IMAGE_REPO}:${NEXTCLOUD_VERSION}"
LATEST_TAG="${IMAGE_REPO}:latest"

echo "==> Building ${VERSION_TAG} (context: ${CONTEXT_DIR})"
docker build \
    --build-arg "NEXTCLOUD_VERSION=${NEXTCLOUD_VERSION}" \
    -t "${VERSION_TAG}" \
    "${CONTEXT_DIR}"

if [ "$SKIP_SCAN" -eq 1 ]; then
    echo "==> Skipping Trivy scan (--skip-scan)"
else
    echo "==> Scanning ${VERSION_TAG} with Trivy (severity: ${SEVERITY})"
    TRIVY_ARGS=(image --severity "${SEVERITY}" --exit-code 1 --no-progress)
    if [ "$IGNORE_UNFIXED" -eq 1 ]; then
        TRIVY_ARGS+=(--ignore-unfixed)
    fi
    if [ -f "${CONTEXT_DIR}/.trivyignore" ]; then
        TRIVY_ARGS+=(--ignorefile "${CONTEXT_DIR}/.trivyignore")
    fi
    if ! trivy "${TRIVY_ARGS[@]}" "${VERSION_TAG}"; then
        echo "==> Trivy found ${SEVERITY} vulnerabilities. Not pushing ${VERSION_TAG}." >&2
        exit 1
    fi
    echo "==> Scan clean"
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo "==> --dry-run set, not pushing"
    exit 0
fi

echo "==> Pushing ${VERSION_TAG}"
docker push "${VERSION_TAG}"

if [ "$PUSH_LATEST" -eq 1 ]; then
    docker tag "${VERSION_TAG}" "${LATEST_TAG}"
    echo "==> Pushing ${LATEST_TAG}"
    docker push "${LATEST_TAG}"
fi

echo "==> Done"
