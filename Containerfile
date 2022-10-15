FROM debian:bullseye-slim
RUN apt-get update && apt-get dist-upgrade -y && apt-get -y install \
    build-essential \
    diffutils \
    git \
    python3 \
    wget \
    cmake \
    libfdt-dev \
    squashfs-tools \
    && apt-get autoclean && apt-get autoremove

RUN git clone https://github.com/dangowrt/owrt-ubi-installer.git /build
WORKDIR /build
RUN ./build_installer.sh
