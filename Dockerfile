FROM alpine:3.20

LABEL description="rutorrent based on alpinelinux" \
  maintainer="KDTheory <kdarmondev@gmail.com>"

ENV UID=991 \
  GID=991 \
  PORT_RTORRENT=45000 \
  MODE_DHT=off \
  PORT_DHT=6881 \
  PEER_EXCHANGE=no \
  DOWNLOAD_DIRECTORY=/data/downloads \
  CHECK_PERM_DATA=true \
  HTTP_AUTH=false

RUN apk --update --no-cache add \
  7zip bash curl curl-dev ffmpeg ffmpeg-dev findutils git jq \
  libmediainfo libmediainfo-dev libzen libzen-dev mediainfo \
  mktorrent nginx openssl php82 php82-bcmath php82-ctype \
  php82-curl php82-dom php82-fpm php82-mbstring php82-opcache \
  php82-openssl php82-pecl-apcu php82-phar php82-session \
  php82-sockets php82-xml php82-zip rtorrent s6 sox su-exec unzip

# Install ruTorrent
ARG RUTORRENT_VERSION=4.3.9
RUN mkdir -p /rutorrent/app \
  && wget -q https://github.com/Novik/ruTorrent/archive/v${RUTORRENT_VERSION}.tar.gz \
  && tar xzf v${RUTORRENT_VERSION}.tar.gz --strip-components=1 -C /rutorrent/app \
  && rm -f v${RUTORRENT_VERSION}.tar.gz

RUN git clone https://github.com/Micdu70/geoip2-rutorrent.git /rutorrent/app/plugins/geoip2 && \
  git clone https://github.com/Micdu70/rutorrent-ratiocolor.git /rutorrent/app/plugins/ratiocolor


COPY rootfs /
RUN chmod 775 /usr/local/bin/*
VOLUME /data /config
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/startup"]
CMD ["/bin/s6-svscan", "/etc/s6.d"]
