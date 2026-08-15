# ops-toolbox

A minimal [Wolfi](https://github.com/wolfi-dev)-based image built with
[`apko`](https://github.com/chainguard-dev/apko), carrying the handful of
tools (SSH, ping,
Wake-on-LAN) — built once, pinned, and Trivy-scanned.

Published as [`aatind/ops-toolbox`](https://hub.docker.com/r/aatind/ops-toolbox)
on Docker Hub.

## What's in it

- `bash`
- `openssh-client` (`ssh`)
- `sshpass`
- `iputils` (`ping`)
- `socat` — used for sending Wake-on-LAN magic packets over UDP broadcast
  (see below); no dedicated WoL package exists in the Wolfi repo, and this
  avoids a raw-socket dependency for that specific need
- `ca-certificates-bundle`

Runs as a fixed non-root uid/gid `10001` by default (see `apko.yaml`). Tools
in this image that need `CAP_NET_RAW` (`ping`) still need the same
`securityContext.capabilities.add: [NET_RAW]` in the pod spec as before —
that's a Linux capability granted by the CronJob's pod spec, independent of
how the image itself is built.

## Why Wolfi + apko, and not a Dockerfile

Wolfi is a rolling-release, glibc-based distro purpose-built for minimal,
scannable container images — no shell history of stale package versions to
accumulate CVEs against, and Trivy understands its advisory feed natively.
`apko` builds an OCI image directly from a declarative package list
(`apko.yaml`) with no Dockerfile, no `RUN` layers, and nothing to purge
afterward — there's no build toolchain to accidentally leave behind because
nothing is ever compiled inside the image.

## Wake-on-LAN usage

There's no bundled WoL script (`apko` doesn't have a `COPY`-equivalent for
arbitrary files without packaging one as its own `apk`, which would be
overkill for a two-line script) — construct the magic packet inline with
`socat`, e.g. in a `CronJob`'s `args`:

```sh
send_wol() {
  mac="$1"
  bcast="${2:-255.255.255.255}"
  hex=$(echo "$mac" | tr -d ":")
  packet=""
  for i in 1 2 3 4 5 6; do packet="${packet}\xff"; done
  for i in $(seq 1 16); do
    packet="${packet}\x${hex:0:2}\x${hex:2:2}\x${hex:4:2}\x${hex:6:2}\x${hex:8:2}\x${hex:10:2}"
  done
  printf "$packet" | socat - UDP-DATAGRAM:${bcast}:9,broadcast
}

send_wol d0:50:99:d9:49:2c
```

## Build

```sh
apko build apko.yaml aatind/ops-toolbox:dev /tmp/ops-toolbox.tar --arch host
docker load < /tmp/ops-toolbox.tar
```

## Build, scan, and publish

```sh
brew install apko trivy   # one-time
docker login              # one-time, needs push access to aatind/ops-toolbox

scripts/build-and-push.sh
```

Images are tagged by build date (`YYYYMMDD`), not an upstream version —
Wolfi is rolling-release, so there's no discrete version number to track. Reference the dated tag
from gitops, not `:latest`, so deployments stay reproducible; rerun the
script (bumping the date) to pick up newer Wolfi package builds.

Useful flags:

- `--tag TAG` — override the tag (default: today's date).
- `--platforms LIST` — override the target `apko` archs (default `x86_64,aarch64`).
- `--dry-run` — build and scan every platform, but don't push.
- `--no-latest` — push the dated tag only, skip updating `:latest`.
- `--severity LIST` — override the failing severities (default `HIGH,CRITICAL`).
- `--include-unfixed` — also fail on vulnerabilities with no fix available yet.
- `--skip-scan` — bypass Trivy entirely (not recommended).

Run `scripts/build-and-push.sh --help` for the full list.
