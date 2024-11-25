# Étape 1 : Builder (compilation des dépendances)
FROM alpine:3.20 AS builder

ARG UNRAR_VER=7.0.9
ARG CURL_VER=7.88.1

# Installer les dépendances nécessaires pour la compilation
RUN apk --update --no-cache add \
    autoconf \
    automake \
    binutils \
    build-base \
    cmake \
    cppunit-dev \
    curl-dev \
    openssl-dev \
    libtool \
    linux-headers \
    zlib-dev \
    git

# Étape 1.1 : Installer unrar
RUN cd /tmp \
  && wget https://www.rarlab.com/rar/unrarsrc-${UNRAR_VER}.tar.gz -O unrar.tar.gz \
  && tar -xzf unrar.tar.gz \
  && cd unrar \
  && make -f makefile \
  && install -Dm 755 unrar /usr/bin/unrar \
  && rm -rf /tmp/*

# Étape 1.2 : Télécharger et compiler c-ares
RUN git clone --depth=1 https://github.com/c-ares/c-ares.git /tmp/c-ares \
  && cd /tmp/c-ares \
  && autoreconf -fi \
  && ./configure --prefix=/usr/local/cares \
  && make -j$(nproc) \
  && make install \
  && rm -rf /tmp/*

# Étape 1.3 : Télécharger et compiler curl avec c-ares
RUN wget https://curl.se/download/curl-${CURL_VER}.tar.gz -O /tmp/curl.tar.gz \
  && tar xzf /tmp/curl.tar.gz -C /tmp \
  && cd /tmp/curl-${CURL_VER} \
  && autoreconf -fi \
  && ./configure --enable-ares=/usr/local/cares --prefix=/usr/local/curl --with-openssl \
  && make -j$(nproc) V=1 \
  && make install \
  && rm -rf /tmp/*

# Étape 1.4 : Build dumptorrent
RUN git clone --depth=1 https://github.com/TheGoblinHero/dumptorrent.git /tmp/dumptorrent \
  && cd /tmp/dumptorrent \
  && sed -i '1i#include <sys/time.h>' scrapec.c \ 
  && mkdir build \
  && cd build \
  && cmake .. \
  && make -j$(nproc) \
  && install -Dm 755 dumptorrent /usr/bin/dumptorrent

# Étape 2 : Image finale (runtime)
FROM alpine:3.20

LABEL description="rutorrent basé sur Alpine Linux" maintainer="KDTheory <kdarmondev@gmail.com>"

ENV UID=991 GID=991 PORT_RTORRENT=45000 MODE_DHT=off PORT_DHT=6881 PEER_EXCHANGE=no DOWNLOAD_DIRECTORY=/data/downloads CHECK_PERM_DATA=true HTTP_AUTH=false

# Copier uniquement les binaires nécessaires depuis le builder
COPY --from=builder /usr/bin/unrar /usr/bin/
COPY --from=builder /usr/bin/dumptorrent /usr/bin/
COPY --from=builder /usr/local/curl/bin/curl /usr/bin/
COPY --from=builder /usr/local/curl/lib/libcurl.so* /usr/lib/

# Installer uniquement les dépendances nécessaires au runtime
RUN apk --update --no-cache add \
    bash curl ffmpeg mediainfo rtorrent s6 sox su-exec unzip php82 php82-fpm nginx

# Installer ruTorrent
ARG RUTORRENT_VERSION=4.3.9
RUN mkdir -p /rutorrent/app \
  && wget https://github.com/Novik/ruTorrent/archive/v${RUTORRENT_VERSION}.tar.gz -O rutorrent.tar.gz \
  && tar xzf rutorrent.tar.gz --strip-components=1 -C /rutorrent/app \
  && rm rutorrent.tar.gz

# Ajouter des plugins supplémentaires à ruTorrent
RUN git clone --depth=1 https://github.com/Micdu70/geoip2-rutorrent.git /rutorrent/app/plugins/geoip2 \
    && git clone --depth=1 https://github.com/Micdu70/rutorrent-ratiocolor.git /rutorrent/app/plugins/ratiocolor

# Préparer les répertoires nécessaires pour l'exécution
RUN mkdir -p /run/rtorrent /run/nginx /run/php

# Supprimer les outils inutiles pour réduire la taille de l'image finale
RUN apk del --purge git

# Copier les fichiers nécessaires depuis le répertoire racine du projet (si existant)
COPY rootfs /

# Définir les permissions et exposer les volumes et ports nécessaires
RUN chmod +x /usr/local/bin/*
VOLUME ["/data", "/config"]
EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/startup"]
CMD ["/bin/s6-svscan", "/etc/s6.d"]
