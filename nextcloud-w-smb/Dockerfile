# syntax=docker/dockerfile:1
ARG NEXTCLOUD_VERSION=34.0.2

FROM nextcloud:${NEXTCLOUD_VERSION}-apache

# --- smbclient PHP extension -------------------------------------------------
# Installed and enabled in one layer so the compiler toolchain and -dev
# headers never appear in the final image history (nothing to purge later,
# nothing left to scan). `apt-get upgrade` pulls in any Debian point-release
# package fixes published after the upstream base image was built (e.g.
# libheif, libpq5 CVEs that already have a patched package in the trixie
# repo mirror) rather than waiting on nextcloud's next base image rebuild.
RUN set -eux; \
    apt-get update; \
    apt-get upgrade -y; \
    apt-get install -y --no-install-recommends \
        gcc \
        make \
        pkg-config \
        libsmbclient-dev \
        libsmbclient0 \
    ; \
    pecl install smbclient-1.1.2; \
    docker-php-ext-enable smbclient; \
    apt-get purge -y --auto-remove gcc make pkg-config libsmbclient-dev; \
    rm -rf /var/lib/apt/lists/* /tmp/pear ~/.pearrc

# --- run fully non-root, uid/gid 10001 ---------------------------------------
# The upstream image starts as root only to bind :80 and chown volumes on
# first run; entrypoint.sh already runs its occ/install steps as www-data via
# su when it detects it started as root, and skips the su call entirely when
# it's already non-root. So what's needed to run the whole container as a
# fixed unprivileged identity is: port 80 needs root to bind, Apache's
# pid/lock dirs are root-owned, the stock www-data account (33/33) is
# renumbered above 10000 so it can't collide with a real host account and
# satisfies "runAsUser/runAsGroup > 10000"-style admission policies, and
# /usr/local/etc/php/conf.d needs to stay writable since entrypoint.sh writes
# session-handler ini files there on every startup (e.g. redis-session.ini
# when REDIS_HOST is set), not just at build time.
# usermod/groupmod only rewrite /etc/passwd|group, not existing file
# ownership, so everything www-data already owns gets re-chowned afterward.
RUN set -eux; \
    sed -ri 's/^Listen 80$/Listen 8080/' /etc/apache2/ports.conf; \
    sed -ri 's/:80>/:8080>/' /etc/apache2/sites-available/000-default.conf; \
    mkdir -p /var/run/apache2 /var/lock/apache2; \
    groupmod -g 10001 www-data; \
    usermod -u 10001 -g 10001 www-data; \
    chown -R 10001:10001 \
        /var/www \
        /var/run/apache2 \
        /var/lock/apache2 \
        /var/log/apache2 \
        /var/cache/apache2 \
        /usr/local/etc/php/conf.d

EXPOSE 8080
USER 10001:10001

ENTRYPOINT ["/entrypoint.sh"]
CMD ["apache2-foreground"]
