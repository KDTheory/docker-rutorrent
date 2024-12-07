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

# Étape 1.1 : Télécharger et compiler unrar avec vérification explicite
RUN mkdir -p /tmp/cache/unrar && cd /tmp/cache/unrar && \
  if [ ! -f unrar-${UNRAR_VER}.built ]; then \
  wget https://www.rarlab.com/rar/unrarsrc-${UNRAR_VER}.tar.gz -O unrar.tar.gz && \
  tar -xzf unrar.tar.gz && cd unrar && \
  make -f makefile && install -Dm 755 unrar /usr/bin/unrar && \
  touch unrar-${UNRAR_VER}.built; \
  fi

# Étape 1.2 : Télécharger et compiler c-ares avec vérification explicite
RUN mkdir -p /tmp/cache/c-ares && cd /tmp/cache/c-ares && \
  if [ ! -d c-ares-${CURL_VER} ]; then \
  git clone --depth=1 https://github.com/c-ares/c-ares.git . && \
  autoreconf -fi && ./configure --prefix=/usr/local/cares && make -j$(nproc) && make install; \
  fi

# Étape 1.3 : Télécharger et compiler curl avec c-ares avec vérification explicite
RUN mkdir -p /tmp/cache/curl && cd /tmp/cache/curl && \
  if [ ! -f curl-${CURL_VER}.built ]; then \
  wget https://curl.se/download/curl-${CURL_VER}.tar.gz -O curl.tar.gz && \
  tar xzf curl.tar.gz --strip-components=1 && autoreconf -fi && \
  ./configure --enable-ares=/usr/local/cares --prefix=/usr/local/curl --with-openssl && \
  make -j$(nproc) V=1 && make install && touch curl-${CURL_VER}.built; \
  fi

# Étape 1.4 : Build dumptorrent avec vérification explicite
RUN mkdir -p /tmp/cache/dumptorrent && cd /tmp/cache/dumptorrent && \
  if [ ! -d dumptorrent-built ]; then \
  git clone --depth=1 https://github.com/TheGoblinHero/dumptorrent.git . && \
  sed -i '1i#include <sys/time.h>' scrapec.c && mkdir build && cd build && \
  cmake .. && make -j$(nproc) && install -Dm 755 dumptorrent /usr/bin/dumptorrent; \
  fi

# Étape finale : Image runtime minimale
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
  7zip \
  bash \
  curl \
  curl-dev \
  ffmpeg \
  ffmpeg-dev \
  findutils \
  git \
  libmediainfo \
  libmediainfo-dev \
  libzen \
  libzen-dev \
  mediainfo \
  mktorrent \
  nginx \
  openssl \
  php82 \
  php82-bcmath \
  php82-ctype \
  php82-curl \
  php82-dom \
  php82-fpm \
  php82-mbstring \
  php82-opcache \
  php82-openssl \
  php82-pecl-apcu \
  php82-phar \
  php82-session \
  php82-sockets \
  php82-xml \
  php82-zip \
  rtorrent \
  s6 \
  sox \
  su-exec \
  unzip

# Installer ruTorrent
ARG RUTORRENT_VERSION=5.1.1

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

CMD tail -f /tmp/rutorrent*.log /tmp/rtorrent*.log &

ENTRYPOINT ["/usr/local/bin/startup"]
CMD ["/bin/s6-svscan", "/etc/s6.d"]
