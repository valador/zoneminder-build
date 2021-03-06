# syntax=docker/dockerfile:experimental
ARG ZM_VERSION=master
ARG S6_ARCH=amd64
ARG ES_VERSION=master

#####################################################################
#                                                                   #
# Download ES                                                       #
#                                                                   #
#####################################################################
FROM alpine:latest AS eventserverdownloader
ARG ES_VERSION
WORKDIR /eventserverdownloader

RUN set -x \
    && apk add git \
    && git clone https://github.com/pliablepixels/zmeventnotification.git . \
    && git checkout ${ES_VERSION}

#####################################################################
#                                                                   #
# Download Zoneminder Source Code                                   #
# Parse control file for all runtime and build dependencies         #
#                                                                   #
#####################################################################
FROM python:alpine as zm-source
ARG ZM_VERSION
WORKDIR /zmsource

RUN set -x \
    && apk add \
        git \
    && git clone https://github.com/ZoneMinder/zoneminder.git . \
    && git submodule update --init --recursive \
    && git checkout ${ZM_VERSION} \
    && git submodule update --init --recursive

COPY zoneminder-base/parse_control.py .

# This parses the control file located at distros/ubuntu2004/control
# It outputs zoneminder_control which only includes requirements for zoneminder
# This prevents equivs-build from being confused when there are multiple packages
RUN set -x \
    && python3 -u parse_control.py

#####################################################################
#                                                                   #
# Convert rootfs to LF using dos2unix                               #
# Alleviates issues when git uses CRLF on Windows                   #
#                                                                   #
#####################################################################
FROM alpine:latest as zm-rootfs-converter
WORKDIR /rootfs

RUN set -x \
    && apk add --repository=http://dl-cdn.alpinelinux.org/alpine/edge/community/ \
        dos2unix

COPY zoneminder-base/root .
RUN set -x \
    && find . -type f -print0 | xargs -0 -n 1 -P 4 dos2unix

#####################################################################
#                                                                   #
# Convert rootfs to LF using dos2unix                               #
# Alleviates issues when git uses CRLF on Windows                   #
#                                                                   #
#####################################################################
FROM alpine:latest as es-rootfs-converter
WORKDIR /rootfs

RUN set -x \
    && apk add --repository=http://dl-cdn.alpinelinux.org/alpine/edge/community/ \
        dos2unix

COPY eventserver-base/root .
RUN set -x \
    && find . -type f -print0 | xargs -0 -n 1 -P 4 dos2unix

#####################################################################
#                                                                   #
# Download and extract s6 overlay                                   #
#                                                                   #
#####################################################################
FROM alpine:latest as s6downloader
# Required to persist build arg
ARG S6_ARCH
WORKDIR /s6downloader

RUN set -x \
    && wget -O /tmp/s6-overlay.tar.gz "https://github.com/just-containers/s6-overlay/releases/latest/download/s6-overlay-${S6_ARCH}.tar.gz" \
    && mkdir -p /tmp/s6 \
    && tar zxvf /tmp/s6-overlay.tar.gz -C /tmp/s6 \
    && cp -r /tmp/s6/* .

RUN set -x \
    && wget -O /tmp/socklog-overlay.tar.gz "https://github.com/just-containers/socklog-overlay/releases/latest/download/socklog-overlay-${S6_ARCH}.tar.gz" \
    && mkdir -p /tmp/socklog \
    && tar zxvf /tmp/socklog-overlay.tar.gz -C /tmp/socklog \
    && cp -r /tmp/socklog/* .

#####################################################################
#                                                                   #
# Prepare base-image with core programs + repository                #
#                                                                   #
#####################################################################
FROM debian:buster as base-image-core

# Skip interactive post-install scripts
ENV DEBIAN_FRONTEND=noninteractive

RUN set -x \
    && apt-get update \
    && apt-get install -y \
        ca-certificates \
        gnupg \
        wget \
    && rm -rf /var/lib/apt/lists/*

# Required for libmp4v2-dev
RUN set -x \
    && echo "deb [trusted=yes] https://zmrepo.zoneminder.com/debian/release-1.34 buster/" > /etc/apt/sources.list.d/zoneminder.list \
    && wget -O - https://zmrepo.zoneminder.com/debian/archive-keyring.gpg | apt-key add -

#####################################################################
#                                                                   #
# Build packages containing build and runtime dependencies          #
# for installation in later stages                                  #
#                                                                   #
#####################################################################
FROM base-image-core as package-builder
WORKDIR /packages

# Install base toolset
RUN set -x \
    && apt-get update \
    && apt-get install -y \
        devscripts

# Create runtime package
RUN --mount=type=bind,target=/tmp/control,source=/zmsource/zoneminder_control,from=zm-source,rw \
    set -x \
    && equivs-build /tmp/control \
    && ls | grep -P \(zoneminder_\)\(.*\)\(\.deb\) | xargs -I {} mv {} runtime-deps.deb

# Create build-deps package
RUN --mount=type=bind,target=/tmp/control,source=/zmsource/zoneminder_control,from=zm-source,rw \
    set -x \
    && mk-build-deps /tmp/control \
    && ls | grep -P \(build-deps\)\(.*\)\(\.deb\) | xargs -I {} mv {} build-deps.deb

#####################################################################
#                                                                   #
# Install runtime dependencies                                      #
# Does not include shared lib dependencies as those are resolved    #
# after building. Installed in final-image                          #
#                                                                   #
#####################################################################
FROM base-image-core as base-image

# Install ZM Dependencies
# Don't want recommends of ZM
RUN --mount=type=bind,target=/tmp/runtime-deps.deb,source=/packages/runtime-deps.deb,from=package-builder,rw \
    set -x \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ./tmp/runtime-deps.deb \
    && rm -rf /var/lib/apt/lists/*

#####################################################################
#                                                                   #
# Install runtime + build dependencies                              #
# Build Zoneminder                                                  #
#                                                                   #
#####################################################################
FROM package-builder as builder
WORKDIR /zmbuild
# Yes WORKDIR is overwritten but this is more a comment
# to specify the final WORKDIR

# Install ZM Buid and Runtime Dependencies
# Need to install runtime dependencies here as well
# because we don't want devscripts in the base-image
# This results in runtime dependencies being installed twice to avoid additional bloating
WORKDIR /packages
RUN set -x \
    && apt-get update \
    && apt-get install -y \
        ./runtime-deps.deb \
        ./build-deps.deb

WORKDIR /zmbuild
RUN --mount=type=bind,target=/zmbuild,source=/zmsource,from=zm-source,rw \
    set -x \
    && cmake \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_SKIP_RPATH=ON \
        -DCMAKE_VERBOSE_MAKEFILE=OFF \
        -DCMAKE_COLOR_MAKEFILE=ON \
        -DZM_RUNDIR=/zoneminder/run \
        -DZM_SOCKDIR=/zoneminder/run \
        -DZM_TMPDIR=/zoneminder/tmp \
        -DZM_LOGDIR=/zoneminder/logs \
        -DZM_WEBDIR=/var/www/html \
        -DZM_CONTENTDIR=/data \
        -DZM_CACHEDIR=/zoneminder/cache \
        -DZM_CGIDIR=/zoneminder/cgi-bin \
        -DZM_WEB_USER=www-data \
        -DZM_WEB_GROUP=www-data \
        -DCMAKE_INSTALL_SYSCONFDIR=config \
        -DZM_CONFIG_DIR=/config \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        . \
    && make \
    && make DESTDIR="/zminstall" install

# Move default config location
RUN set -x \
    && mv /zminstall/config /zminstall/zoneminder/defaultconfig

#####################################################################
#                                                                   #
# Install ZoneMinder                                                #
# Create required folders                                           #
# Install additional dependencies                                   #
#                                                                   #
#####################################################################
FROM base-image as zm-final-build
ARG ZM_VERSION

# Add Nginx Repo
RUN set -x \
    && echo "deb https://nginx.org/packages/mainline/debian/ buster nginx" > /etc/apt/sources.list.d/nginx.list \
    && apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62

# Install additional services required by ZM ("Recommends")
# PHP-fpm not required for apache
RUN set -x \
    && apt-get update \
    && apt-get install -y \
        fcgiwrap \
        mailutils \
        msmtp \
        nginx \
        php-fpm \
        tzdata \
    && rm -rf /var/lib/apt/lists/*

# Remove rsyslog as its unneeded and hangs the container on shutdown
RUN set -x \
    && apt-get -y remove rsyslog || true

## Create www-data user
RUN set -x \
    && groupmod -o -g 911 www-data \
    && usermod -o -u 911 www-data

# Install ZM
COPY --chown=www-data --chmod=755 --from=builder /zminstall /

# Install s6 overlay
COPY --from=s6downloader /s6downloader /

# Copy rootfs
COPY --from=zm-rootfs-converter /rootfs /

# Create required folders
RUN set -x \
    && mkdir -p \
        /run/php \
        /data \
        /config \
        /zoneminder/run \
        /zoneminder/cache \
        /zoneminder/logs \
        /zoneminder/tmp \
        /log \
    && chown -R www-data:www-data \
        /data \
        /config \
        /zoneminder \
    && chmod -R 755 \
        /data \
        /config \
        /zoneminder \
        /log \
    && chown -R nobody:nogroup \
        /log

# Reconfigure nginx and php logs
# Configure msmtp
RUN set -x \
    && ln -sf /proc/self/fd/1 /var/log/nginx/access.log \
    && ln -sf /proc/self/fd/1 /var/log/nginx/error.log \
    && ln -sf /proc/self/fd/1 /var/log/php7.3-fpm.log \
    && ln -sf /usr/bin/msmtp /usr/lib/sendmail \
    && ln -sf /usr/bin/msmtp /usr/sbin/sendmail \
    && rm -rf /etc/nginx/conf.d

LABEL \
    com.github.alexyao2015.zoneminder_version=${ZM_VERSION}

# System Variables
ENV \
    S6_FIX_ATTRS_HIDDEN=1 \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    APACHE_RUN_USER=www-data \
    APACHE_RUN_GROUP=www-data \
    SOCKLOG_TIMESTAMP_FORMAT="" \
    MAX_LOG_SIZE_BYTES=1000000 \
    MAX_LOG_NUMBER=10

# Default User Variables
ENV \
    MYSQL_HOST=db \
    PHP_MAX_CHILDREN=120 \
    PHP_START_SERVERS=12 \
    PHP_MIN_SPARE_SERVERS=6 \
    PHP_MAX_SPARE_SERVERS=18 \
    PHP_MEMORY_LIMIT=2048M \
    PHP_MAX_EXECUTION_TIME=600 \
    PHP_MAX_INPUT_VARIABLES=3000 \
    PHP_MAX_INPUT_TIME=600 \
    FCGIWRAP_PROCESSES=15 \
    FASTCGI_BUFFERS_CONFIGURATION_STRING="64 4K" \
    PUID=911 \
    PGID=911 \
    TZ="America/Chicago" \
    USE_SECURE_RANDOM_ORG=1

CMD ["/init"]

#####################################################################
#                                                                   #
# Install ES                                                        #
# Apply changes to default ES config                                #
#                                                                   #
#####################################################################
FROM zm-final-build as es-final-build
ARG ES_VERSION

RUN set -x \
    && apt-get update \
    && apt-get install -y \
        build-essential \
        libjson-perl \
    && PERL_MM_USE_DEFAULT=1 \
    && yes | perl -MCPAN -e "install Net::WebSocket::Server" \
    && yes | perl -MCPAN -e "install LWP::Protocol::https" \
    && yes | perl -MCPAN -e "install Config::IniFiles" \
    && yes | perl -MCPAN -e "install Time::Piece" \
    && yes | perl -MCPAN -e "install Net::MQTT::Simple" \
    && yes | perl -MCPAN -e "install Net::MQTT::Simple::Auth" \
    && apt-get remove --purge -y \
        build-essential \
    && rm -rf /var/lib/apt/lists/*

RUN --mount=type=bind,target=/tmp/eventserver,source=/eventserverdownloader,from=eventserverdownloader,rw \
    set -x \
    && cd /tmp/eventserver \
    && mkdir -p /zoneminder/defaultconfiges \
    && TARGET_CONFIG=/zoneminder/defaultconfiges \
        MAKE_CONFIG_BACKUP='' \
        ./install.sh \
            --install-es \
            --no-install-hook \
            --install-config \
            --no-interactive \
            --no-pysudo \
            --no-hook-config-upgrade \
    && mkdir -p /zoneminder/estools \
    && cp ./tools/* /zoneminder/estools

# Fix default es config
# https://stackoverflow.com/a/16987794
RUN set -x \
    && sed -i "/^\[general\]$/,/^\[/ s|^secrets.*=.*|secrets=/config/secrets.ini|" /zoneminder/defaultconfiges/zmeventnotification.ini \
    && sed -i "/^\[fcm\]$/,/^\[/ s|^token_file.*=.*|token_file=/config/tokens.txt|" /zoneminder/defaultconfiges/zmeventnotification.ini \
    && sed -i "/^\[customize\]$/,/^\[/ s|^console_logs.*=.*|console_logs=yes|" /zoneminder/defaultconfiges/zmeventnotification.ini \
    && sed -i "/^\[customize\]$/,/^\[/ s|^use_hooks.*=.*|use_hooks=no|" /zoneminder/defaultconfiges/zmeventnotification.ini \
    && sed -i "/^\[network\]$/,/^\[/ s|^.*address.*=.*|address=0.0.0.0|" /zoneminder/defaultconfiges/zmeventnotification.ini \
    && sed -i "/^\[auth\]$/,/^\[/ s|^enable.*=.*|enable=no|" /zoneminder/defaultconfiges/zmeventnotification.ini

# Fix default es secrets
RUN set -x \
    && sed -i "/^\[secrets\]$/,/^\[/ s|^ES_CERT_FILE.*=.*|ES_CERT_FILE=/config/ssl/cert.cer|" /zoneminder/defaultconfiges/secrets.ini \
    && sed -i "/^\[secrets\]$/,/^\[/ s|^ES_KEY_FILE.*=.*|ES_KEY_FILE=/config/ssl/key.pem|" /zoneminder/defaultconfiges/secrets.ini

# Copy rootfs
COPY --from=es-rootfs-converter /rootfs /

ENV \
    ES_DEBUG_ENABLED=1 \
    ES_COMMON_NAME=localhost \
    ES_ENABLE_AUTH=0 \
    ES_ENABLE_DHPARAM=1 \
    USE_SECURE_RANDOM_ORG=1

LABEL \
    com.github.alexyao2015.es_version=${ES_VERSION}

# Face rekognition start build
FROM es-final-build as es-face-build-1
RUN apt-get install -y --fix-missing \
    libyaml-perl \
    libavutil-dev \
    ffmpeg \
    libvlc-dev \
    libvlccore-dev \
    vlc-bin \
    vlc-plugin-base \
    vlc-plugin-video-output \
    ssmtp \
    net-tools \
    sudo \
    make \
    gcc \
    cmake \
    gfortran \
    git \
    wget \
    curl \
    graphicsmagick \
    libgraphicsmagick1-dev \
    libatlas-base-dev \
    libavcodec-dev \
    libavformat-dev \
    libgtk2.0-dev \
    libjpeg-dev \
    liblapack-dev \
    libswscale-dev \
    pkg-config \
    python3-dev \
    python3-numpy \
	python3-setuptools \
    software-properties-common \
    zip \
    && apt-get clean && rm -rf /tmp/* /var/tmp/*
RUN cd ~ && \
    mkdir -p dlib && \
    git clone -b 'v19.22' --single-branch https://github.com/davisking/dlib.git dlib/
# RUN cd  ~/dlib/ && \
# 	mkdir -p build; cd build; cmake .. -DDLIB_USE_CUDA=0 -DUSE_AVX_INSTRUCTIONS=1; cmake --build .
RUN cd  ~/dlib/ && \
	python3 setup.py install --no DLIB_USE_CUDA
RUN	apt-get -y install python3-pip && \
	apt-get -y install libopenblas-dev liblapack-dev libblas-dev && \
	pip3 install future && \
	pip3 install /root/zmeventnotification && \
	pip3 install face_recognition && \
	rm -r /root/zmeventnotification/zmes_hook_helpers && \
	cd /root/ && \
	mkdir -p models/tinyyolov3 && \
	wget https://pjreddie.com/media/files/yolov3-tiny.weights -O models/tinyyolov3/yolov3-tiny.weights && \
	wget https://raw.githubusercontent.com/pjreddie/darknet/master/cfg/yolov3-tiny.cfg -O models/tinyyolov3/yolov3-tiny.cfg && \
	wget https://raw.githubusercontent.com/pjreddie/darknet/master/data/coco.names -O models/tinyyolov3/coco.names && \
	mkdir -p models/yolov3 && \
	wget https://raw.githubusercontent.com/pjreddie/darknet/master/cfg/yolov3.cfg -O models/yolov3/yolov3.cfg && \
	wget https://raw.githubusercontent.com/pjreddie/darknet/master/data/coco.names -O models/yolov3/coco.names && \
	wget https://pjreddie.com/media/files/yolov3.weights -O models/yolov3/yolov3.weights && \
	mkdir -p models/tinyyolov4 && \
	wget https://github.com/AlexeyAB/darknet/releases/download/darknet_yolo_v4_pre/yolov4-tiny.weights -O models/tinyyolov4/yolov4-tiny.weights && \
	wget https://raw.githubusercontent.com/AlexeyAB/darknet/master/cfg/yolov4-tiny.cfg -O models/tinyyolov4/yolov4-tiny.cfg && \
	wget https://raw.githubusercontent.com/pjreddie/darknet/master/data/coco.names -O models/tinyyolov4/coco.names && \
	mkdir -p models/yolov4 && \
	wget https://raw.githubusercontent.com/AlexeyAB/darknet/master/cfg/yolov4.cfg -O models/yolov4/yolov4.cfg && \
	wget https://raw.githubusercontent.com/pjreddie/darknet/master/data/coco.names -O models/yolov4/coco.names && \
	wget https://github.com/AlexeyAB/darknet/releases/download/darknet_yolo_v3_optimal/yolov4.weights -O models/yolov4/yolov4.weights

FROM es-face-build-1 as es-face-build-2
RUN	cd /root && \
	wget -q -O opencv.zip https://github.com/opencv/opencv/archive/4.5.2.zip && \
	wget -q -O opencv_contrib.zip https://github.com/opencv/opencv_contrib/archive/4.5.2.zip && \
	unzip opencv.zip && \
	unzip opencv_contrib.zip && \
	mv $(ls -d opencv-*) opencv && \
	mv opencv_contrib-4.5.2 opencv_contrib && \
	rm *.zip && \
	cd /root/opencv && \
	mkdir build && \
	cd build && \
	cmake -D CMAKE_BUILD_TYPE=RELEASE -D CMAKE_INSTALL_PREFIX=/usr/local -D INSTALL_PYTHON_EXAMPLES=OFF -D INSTALL_C_EXAMPLES=OFF -D OPENCV_ENABLE_NONFREE=ON -D OPENCV_EXTRA_MODULES_PATH=/root/opencv_contrib/modules -D HAVE_opencv_python3=ON -D PYTHON_EXECUTABLE=/usr/bin/python3 -D PYTHON2_EXECUTABLE=/usr/bin/python2 -D BUILD_EXAMPLES=OFF .. >/dev/null && \
	make -j4 && \
	make install && \
	cd /root && \
	rm -r opencv*

