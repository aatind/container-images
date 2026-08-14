# nextcloud-w-smb

A hardened [`nextcloud`](https://hub.docker.com/_/nextcloud) (Apache variant) image
with the `smbclient` PHP extension built in, for using SMB/CIFS shares as
external storage in Nextcloud.

Published as [`aatind/nextcloud`](https://hub.docker.com/r/aatind/nextcloud) on
Docker Hub.

## What's different from upstream `nextcloud:apache`

- **`smbclient` PHP extension** — compiled via PECL against `libsmbclient-dev`
  and enabled. Lets Nextcloud's "External storage" app mount SMB/CIFS shares
  natively instead of via a FUSE mount on the host.
- **No leftover build toolchain** — `gcc`, `make`, `pkg-config`, and
  `libsmbclient-dev` are installed and purged in the same `RUN` layer, so the
  final image only carries the runtime `libsmbclient0` shared library, not a
  compiler.
- **Runs fully non-root, uid/gid 10001** — the container runs as a fixed,
  unprivileged identity from PID 1, not just after an internal privilege
  drop. The stock `www-data` account (33/33) is renumbered above 10000 at
  build time — high enough to avoid colliding with a real host account and
  to satisfy `runAsUser`/`runAsGroup` > 10000-style admission policies — and
  every path it owns (`/var/www`, Apache's pid/lock/log/cache dirs,
  `/usr/local/etc/php/conf.d` — entrypoint.sh writes session-handler ini
  files there at every startup, e.g. `redis-session.ini` when `REDIS_HOST`
  is set) is re-chowned to match. Apache listens on `8080` instead of `80`
  (binding <1024 requires root). No `NET_BIND_SERVICE` or other Linux
  capability is needed — map it to a privileged host port with Docker's
  `-p` if you want one.
- Pinned Nextcloud version via build arg (`NEXTCLOUD_VERSION`) and pinned
  `smbclient` PECL version, rather than floating on `latest`.
- **`apt-get upgrade` at build time** — pulls in Debian point-release
  package fixes published after the upstream `nextcloud:apache` image was
  last built, instead of carrying known-fixed CVEs until nextcloud's next
  base image rebuild.

## Build

```sh
docker build --build-arg NEXTCLOUD_VERSION=34.0.2 -t aatind/nextcloud:34.0.2 .
```

This builds for your local machine's architecture only. Published images are
multi-arch (`linux/amd64` + `linux/arm64`) via `scripts/build-and-push.sh` —
see below. If you're building locally to run on a different architecture
than your dev machine (e.g. building on Apple Silicon to run on an x86_64
server), use `docker buildx build --platform linux/amd64 ...` instead, or
you'll hit `exec format error` at container startup.

## Run

```sh
docker run -d \
  --name nextcloud \
  -p 8080:8080 \
  -v nextcloud_html:/var/www/html \
  aatind/nextcloud:34.0.2
```

Nextcloud is then reachable on host port `8080`. Put a reverse proxy (Caddy,
Traefik, nginx) in front for TLS and to expose it on `443`, as you would for
any Nextcloud deployment.

If you bind-mount host directories instead of named volumes, make sure they
are writable by uid/gid `10001` on the host — the container has no root user
available at runtime to `chown` them for you on first launch.

## Build, scan, and publish

`scripts/build-and-push.sh` builds the image for each target platform
(default `linux/amd64,linux/arm64`), scans every platform with
[Trivy](https://trivy.dev/), and — only if every platform comes back clean
of HIGH/CRITICAL vulnerabilities with a known fix — builds and pushes a
proper multi-arch manifest to `aatind/nextcloud` on Docker Hub.

```sh
brew install trivy   # one-time
docker login         # one-time, needs push access to aatind/nextcloud

# one-time: a docker-container buildx builder, needed to push a multi-arch
# manifest (the default "docker" driver can only build/load, not push one)
docker buildx create --name multiarch --driver docker-container --use

scripts/build-and-push.sh --version 34.0.2
```

Useful flags:

- `--platforms LIST` — override the target platforms (default `linux/amd64,linux/arm64`).
- `--dry-run` — build and scan every platform, but don't push.
- `--no-latest` — push the version tag only, skip updating `:latest`.
- `--severity LIST` — override the failing severities (default `HIGH,CRITICAL`).
- `--include-unfixed` — also fail on vulnerabilities with no fix available yet.
- `--skip-scan` — bypass Trivy entirely (not recommended).

Run `scripts/build-and-push.sh --help` for the full list.

### `.trivyignore`

Vulnerabilities that are genuinely out of this image's control (bundled
inside the Nextcloud release tarball itself, not a Debian package we can
`apt-get upgrade`, or an OS package with no fix published yet) are waived in
`.trivyignore`, each with a comment explaining why and when to remove it.
Check that file whenever the scan blocks a push — don't add an entry there
without a real reason it can't be fixed in this Dockerfile.

## Bumping the Nextcloud version

1. Check the new version has an `-apache` tag on
   [Docker Hub](https://hub.docker.com/_/nextcloud/tags).
2. `scripts/build-and-push.sh --version <new-version> --dry-run` to build and
   scan locally first.
3. Re-run without `--dry-run` to publish once you're happy with it.
