# docker-images
Containing container image builds

## Images

| Directory | Published as | What it is |
|---|---|---|
| [`nextcloud-w-smb`](nextcloud-w-smb) | [`aatind/nextcloud`](https://hub.docker.com/r/aatind/nextcloud) | Nextcloud (Apache) with the `smbclient` PHP extension, running fully non-root (uid/gid 10001). |
| [`vaultwarden-hardened`](vaultwarden-hardened) | [`aatind/vaultwarden`](https://hub.docker.com/r/aatind/vaultwarden) | Vaultwarden, patched at build time and running fully non-root (uid/gid 10001) by default. |
| [`ops-toolbox`](ops-toolbox) | [`aatind/ops-toolbox`](https://hub.docker.com/r/aatind/ops-toolbox) | Minimal Wolfi/`apko` image (ssh, sshpass, ping, socat) for [gitops](../gitops) cronjobs, replacing per-run `apk add` against `alpine:latest`. |

Every image here is multi-arch (`linux/amd64` + `linux/arm64`), Trivy-scanned
before every push, and built/published via each directory's own
`scripts/build-and-push.sh` — see each subdirectory's README for specifics.
