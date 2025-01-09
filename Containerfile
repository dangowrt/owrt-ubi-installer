FROM ubuntu:22.04
RUN apt-get update && apt-get dist-upgrade -y && apt-get -y install \
    build-essential \
    diffutils \
    git \
    python3 \
    wget \
    cmake \
    libfdt-dev \
    squashfs-tools \
    zstd \
    && apt-get autoclean && apt-get autoremove

COPY . /build
WORKDIR /build
RUN ./build_installer.sh
