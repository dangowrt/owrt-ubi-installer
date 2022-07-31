FROM fedora:36
RUN dnf -y install \
    @c-development \
    @development-tools \
    @development-libs \
    zlib-static \
    which \
    diffutils \
    python3 \
    wget \
    xz \
    cmake \
    libfdt-devel \
    squashfs-tools \
    && dnf clean all
WORKDIR /build
ENTRYPOINT ["./build_installer.sh"]
