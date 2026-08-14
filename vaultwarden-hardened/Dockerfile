# syntax=docker/dockerfile:1
ARG VAULTWARDEN_VERSION=1.37.1

FROM vaultwarden/server:${VAULTWARDEN_VERSION}

# --- patch level + run fully non-root, uid/gid 10001 -------------------------
# The upstream image runs as root by default (its /start.sh has no
# privilege-drop logic at all — it just execs the binary), and Rocket reads
# its listen port from $ROCKET_PORT at runtime rather than a config file, so
# there's no Apache-style config edit needed to run on an unprivileged port.
# `apt-get upgrade` pulls in Debian point-release fixes published after the
# upstream image was built. /data is the only path the process writes to
# (its sqlite db, attachments, config.json) so it's the only thing to chown.
RUN set -eux; \
    apt-get update; \
    apt-get upgrade -y; \
    rm -rf /var/lib/apt/lists/*; \
    groupadd -g 10001 vaultwarden; \
    useradd -u 10001 -g 10001 -M -s /usr/sbin/nologin vaultwarden; \
    chown -R 10001:10001 /data

USER 10001:10001
