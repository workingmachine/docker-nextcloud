FROM nextcloud:31-apache

RUN set -ex; \
    \
    apt-get update -y -q; \
    apt-get install -y -q --no-install-recommends \
        apt-utils \
    ; \
    apt-get dist-clean

RUN set -ex; \
    \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ffmpeg \
        ghostscript \
#        libmagickcore-7.q16-10-extra < used in base image \
        procps \
        smbclient \
        supervisor \
#       libreoffice \
    ; \
    apt-get dist-clean

# workaround to get xz working
# use older xz version, which does not use a sandbox (Landlock)
# and therefore RHEL does not block
ARG XZ_VERSION=5.4.7
ARG XZ_SHA256="8db6664c48ca07908b92baedcfe7f3ba23f49ef2476864518ab5db6723836e71"
RUN set -ex; \
    # 1. install build tools (gcc, make, ...)
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        wget \
        ca-certificates; \
    \
    # 2. download xz source code
    wget -O /tmp/xz-${XZ_VERSION}.tar.gz https://github.com/tukaani-project/xz/releases/download/v${XZ_VERSION}/xz-${XZ_VERSION}.tar.gz; \
    \
    # 3. verify xz tarball
    cd /tmp; \
    echo "${XZ_SHA256} xz-${XZ_VERSION}.tar.gz" | sha256sum --check -; \
    \
    # 4. unpack
    tar -xzvf xz-${XZ_VERSION}.tar.gz; \
    \
    # 5. compile
    cd xz-${XZ_VERSION}; \
    ./configure --disable-shared --prefix=/usr; \
    make; \
    \
    # 6. replace xz installed distribution binary with self-compiled one
    mv /usr/bin/xz /usr/bin/xz.dist; \
    cp src/xz/xz /usr/bin/xz; \
    \
    # 7. clean up
    cd /; \
    rm -rf /tmp/xz-${XZ_VERSION} /tmp/xz-${XZ_VERSION}.tar.gz; \
    apt-get remove -y build-essential wget; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*;

# install PHP extensions
RUN set -ex; \
    \
    savedAptMark="$(apt-mark showmanual)"; \
    \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libbz2-dev \
#        libetpan-dev < replacement for libc-client-dev \
#        libc-client-dev \
#        libkrb5-dev \
        libsmbclient-dev \
    ; \
    \
#    docker-php-ext-configure imap --with-kerberos --with-imap-ssl; \
    docker-php-ext-install \
        bz2 \
#        imap \
    ; \
    pecl install smbclient; \
    docker-php-ext-enable smbclient; \
    \
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $savedAptMark; \
    ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
        | awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); print so }' \
        | sort -u \
        | xargs -r dpkg-query --search \
        | cut -d: -f1 \
        | sort -u \
        | xargs -rt apt-mark manual; \
    \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    apt-get dist-clean

# set timezone
ENV TZ=Europe/Vienna
RUN set -ex; \
    ln --symbolic --no-dereference --force /usr/share/zoneinfo/$TZ /etc/localtime; \
    echo $TZ > /etc/timezone

# supervisord configuration
RUN set -ex; \
    mkdir --parents /var/log/supervisord /var/run/supervisord

COPY supervisord.conf /
COPY --chown=8005:8005 --chmod=770 cron.sh /
COPY --chown=8005:8005 --chmod=770 officeconnect.sh /

# create user foo
RUN set -ex; \
    useradd --no-create-home --shell /usr/sbin/nologin --uid 8005 foo; \
    usermod --home /nonexistent foo

# Avoid permission error later. This is likely suboptimal but it seems to work.
# The error is: PermissionError: [Errno 13] Permission denied: '/var/log/supervisord/supervisord.log'
RUN set -ex; \
    chown --recursive 8005:8005 /var/log/supervisord /var/run/supervisord

ENV NEXTCLOUD_UPDATE=1

CMD ["/usr/bin/supervisord", "-c", "/supervisord.conf"]
