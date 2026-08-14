# vaultwarden-hardened

A hardened [`vaultwarden/server`](https://hub.docker.com/r/vaultwarden/server)
image: same upstream binary, rebuilt with fresh OS patches and a fixed
non-root identity baked in, rather than relying solely on the deploying
cluster's `securityContext` to enforce it.

Published as [`aatind/vaultwarden`](https://hub.docker.com/r/aatind/vaultwarden)
on Docker Hub.

## What's different from upstream `vaultwarden/server`

- **`apt-get upgrade` at build time** — pulls in Debian point-release
  package fixes published after the upstream image was built, same
  rationale as [`nextcloud-w-smb`](../nextcloud-w-smb).
- **Runs fully non-root, uid/gid 10001 by default** — the upstream image
  runs as root by default (its `/start.sh` has no privilege-drop logic;
  it just `exec`s the binary directly). This image creates a dedicated
  `vaultwarden` account at uid/gid 10001 — high enough to avoid colliding
  with a real host account and to satisfy `runAsUser`/`runAsGroup` >
  10000-style admission policies — chowns `/data` (the only path the
  process writes to: sqlite db, attachments, `config.json`, RSA keys) to
  match, and sets `USER 10001:10001`.
- No port remap needed unlike `nextcloud-w-smb`: Vaultwarden's Rocket web
  framework reads its listen port from `$ROCKET_PORT` at runtime, so binding
  an unprivileged port (e.g. 8080) is just an env var, not a config file
  edit baked into the image.

## Build

```sh
docker build --build-arg VAULTWARDEN_VERSION=1.37.1 -t aatind/vaultwarden:1.37.1 .
```

Builds for your local machine's architecture only — see "Build, scan, and
publish" below for the real multi-arch (`linux/amd64` + `linux/arm64`)
publish flow.

## Run

```sh
docker run -d \
  --name vaultwarden \
  -p 8080:8080 \
  -e ROCKET_PORT=8080 \
  -e DOMAIN=https://your-domain \
  -e ADMIN_TOKEN=<argon2-phc-string> \
  -v vaultwarden_data:/data \
  aatind/vaultwarden:1.37.1
```

If you bind-mount a host directory instead of a named volume, make sure it's
writable by uid/gid `10001` on the host — the container has no root user
available at runtime to `chown` it for you.

## Build, scan, and publish

Same pattern as `nextcloud-w-smb`: builds and Trivy-scans each target
platform locally first, then pushes a multi-arch manifest only if every
platform is clean.

```sh
brew install trivy   # one-time
docker login         # one-time, needs push access to aatind/vaultwarden

# one-time: a docker-container buildx builder, needed to push a multi-arch
# manifest (the default "docker" driver can only build/load, not push one)
docker buildx create --name multiarch --driver docker-container --use

scripts/build-and-push.sh --version 1.37.1
```

Useful flags:

- `--platforms LIST` — override the target platforms (default `linux/amd64,linux/arm64`).
- `--dry-run` — build and scan every platform, but don't push.
- `--no-latest` — push the version tag only, skip updating `:latest`.
- `--severity LIST` — override the failing severities (default `HIGH,CRITICAL`).
- `--include-unfixed` — also fail on vulnerabilities with no fix available yet.
- `--skip-scan` — bypass Trivy entirely (not recommended).

Run `scripts/build-and-push.sh --help` for the full list.

## Bumping the Vaultwarden version

1. Check the new version exists on
   [Docker Hub](https://hub.docker.com/r/vaultwarden/server/tags).
2. `scripts/build-and-push.sh --version <new-version> --dry-run` to build and
   scan locally first.
3. Re-run without `--dry-run` to publish once you're happy with it.
