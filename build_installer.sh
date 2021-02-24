#!/bin/bash

DESTDIR="$PWD"

OPENWRT_GIT_SRC="https://git.openwrt.org/openwrt/staging/dangole.git"
OPENWRT_GIT_BRANCH="linksys-e8450-hackery"

INSTALLERDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
OPENWRT_DIR="${INSTALLERDIR}/openwrt-build-installer"
MKIMAGE="${OPENWRT_DIR}/staging_dir/host/bin/mkimage"

UNFIT="${INSTALLERDIR}/unfit"
[ -x "$UNFIT" ] || cc -o "$UNFIT" -lfdt "${UNFIT}.c" || {
	echo "can't build unfit. please install gcc and libfdt-dev"
	exit 0
}

DTC=
FILEBASE=
WORKDIR=
ITSFILE=

build_openwrt() {
	if [ -d "$OPENWRT_DIR" ]; then
		cd "$OPENWRT_DIR"
		git fetch "$OPENWRT_GIT_SRC" "$OPENWRT_GIT_BRANCH"
		git checkout -f FETCH_HEAD
	else
		git clone ${OPENWRT_GIT_BRANCH:+-b $OPENWRT_GIT_BRANCH} https://git.openwrt.org/openwrt/staging/dangole.git "$OPENWRT_DIR"
		cd "$OPENWRT_DIR"
	fi
	scripts/feeds update -a
	scripts/feeds install -a
	echo "CONFIG_TARGET_mediatek=y" > .config
	echo "CONFIG_TARGET_mediatek_mt7622=y" >> .config
	echo "CONFIG_TARGET_mediatek_mt7622_DEVICE_linksys_e8450-ubi=y" >> .config
	echo "CONFIG_TESTING_KERNEL=y" >> .config
	echo "CONFIG_TARGET_ROOTFS_INITRAMFS=y" >> .config
	echo "CONFIG_TARGET_INITRAMFS_COMPRESSION_XZ=y" >> .config
	echo "CONFIG_TARGET_ROOTFS_INITRAMFS_SEPERATE=y" >> .config
	echo "CONFIG_TARGET_ROOTFS_SQUASHFS=y" >> .config
	echo "CONFIG_PACKAGE_blockd=y" >> .config
	echo "# CONFIG_PACKAGE_kmod-ata-ahci-mtk is not set" >> .config
	echo "# CONFIG_PACKAGE_kmod-ata-core is not set" >> .config
	echo "CONFIG_PACKAGE_kmod-usb-storage=y" >> .config
	echo "CONFIG_PACKAGE_kmod-usb-storage-uas=y" >> .config
	echo "CONFIG_PACKAGE_kmod-fs-vfat=y" >> .config
	echo "CONFIG_PACKAGE_kmod-fs-msdos=y" >> .config
	echo "CONFIG_PACKAGE_kmod-fs-exfat=y" >> .config
	echo "CONFIG_PACKAGE_kmod-fs-f2fs=y" >> .config
	echo "CONFIG_PACKAGE_kmod-fs-ext4=y" >> .config
	echo "CONFIG_PACKAGE_procd-ujail=y" >> .config
	echo "CONFIG_PACKAGE_kmod-nls-utf8=y" >> .config
	echo "CONFIG_PACKAGE_kmod-nls-cp437=y" >> .config
	echo "CONFIG_PACKAGE_kmod-nls-iso8859-1=y" >> .config
	echo "CONFIG_PACKAGE_luci=y" >> .config
	echo "CONFIG_PACKAGE_luci-ssl-openssl=y" >> .config
	echo "CONFIG_PACKAGE_luci-theme-openwrt-2020=y" >> .config
	echo "CONFIG_PACKAGE_nand-utils=y" >> .config
	echo "CONFIG_OPENSSL_OPTIMIZE_SPEED=y" >> .config
	echo "# CONFIG_PACKAGE_libustream-wolfssl is not set" >> .config
	echo "# CONFIG_PACKAGE_wpad-basic-wolfssl is not set" >> .config
	echo "CONFIG_PACKAGE_libustream-openssl=y" >> .config
	echo "CONFIG_PACKAGE_wpad-openssl=y" >> .config
	make oldconfig </dev/null 2>/dev/null 1>/dev/null
	make -j$(nproc)
}

its_add_data() {
	local line
	local in_images=0
	local in_image=0
	local br_level=0
	local img_name
	cat "${ITSFILE}" | while read line; do
		echo "$line"
		if [ "$in_images" = "0" ]; then
			case "$line" in
				*"images {"*)
					in_images=1
					continue;
				;;
			esac
		fi
		if [ "$in_images" = "1" ] && [ "$in_image" = "0" ]; then
			case "$line" in
				*"{"*)
					in_image=1
					img_name="$(echo "$line" | cut -d'{' -f1 | sed 's/ *$//g' )"
					continue;
				;;
			esac
		fi
		if [ "$in_images" = "1" ] && [ "$in_image" = "1" ]; then
			case "$line" in
				*"type = "*)
					echo "data = /incbin/(\"./${img_name}\");"
					;;
				*"{"*)
					br_level=$((br_level + 1))
					continue;
					;;
				*"}"*)
					if [ $br_level -gt 0 ]; then
						br_level=$((br_level - 1))
					else
						in_image=0
					fi
					continue;
					;;
			esac
		fi
	done
}

unfit_image() {
	INFILE="$1"
	FILEBASE="$(basename "$INFILE" .fit)"
	WORKDIR="$(mktemp -d)"
	ITSFILE="${WORKDIR}/image.its"
	mkdir -p "$WORKDIR"
	cd "$WORKDIR"
	"$UNFIT" "$INFILE"
	DTC="$(ls -1 ${OPENWRT_DIR}/build_dir/target-aarch64_cortex-a53_musl/linux-mediatek_mt7622/linux-*/scripts/dtc/dtc)"

	"$DTC" -I dtb -O dts -o "$ITSFILE" "$INFILE" || exit 2

	echo "extracted successfully"

	# figure out exact FIT image type
	CLASSIC=
	EXTERNAL=
	STATIC=
	grep -q "data = " "$ITSFILE" && CLASSIC=1
	grep -q "data-size = " "$ITSFILE" && EXTERNAL=1
	grep -q "data-position = " "$ITSFILE" && STATIC=1

	# filter-out existing data nodes
	grep -v -e "data = " -e "data-size = " -e "data-offset = " -e "data-position = " "$ITSFILE" > "${ITSFILE}.new"
	mv "${ITSFILE}.new" "${ITSFILE}"
}

refit_image() {
	# re-add data nodes from files
	its_add_data > "${ITSFILE}.new"

	MKIMAGE_PARM=""
	[ "$EXTERNAL" = "1" ] && MKIMAGE_PARM="$MKIMAGE_PARM -E -B 0x1000"
	[ "$STATIC" = "1" ] && MKIMAGE_PARM="$MKIMAGE_PARM -p 0x1000"

	PATH="$PATH:$(dirname "$DTC")" "$MKIMAGE" $MKIMAGE_PARM -f "${ITSFILE}.new" "${FILEBASE}-refit.fit"

	dd if="${FILEBASE}-refit.fit" of="${FILEBASE}-installer.fit" bs=$1 conv=sync
}

extract_initrd() {
	[ -e "${WORKDIR}/initrd@1" ] || return 1
	[ -e "${WORKDIR}/initrd" ] && rm -rf "${WORKDIR}/initrd"
	mkdir "${WORKDIR}/initrd"
	xz -d < "${WORKDIR}/initrd@1" | cpio -i -D "${WORKDIR}/initrd"
	rm "${WORKDIR}/initrd@1"
	echo "initrd extracted in ${WORKDIR}/initrd"
	return 0
}

repack_initrd() {
	[ -d "${WORKDIR}/initrd" ] || return 1
	echo "re-compressing initrd..."
	( cd "${WORKDIR}/initrd" ; find . | cpio -o -H newc -R root:root | xz -c -9  --check=crc32 > "${WORKDIR}/initrd@1" )
	return 0
}

allow_mtd_write() {
	"$DTC" -I dtb -O dts -o "${WORKDIR}/fdt@1.dts" "${WORKDIR}/fdt@1"
	rm "${WORKDIR}/fdt@1"
	grep -v 'read-only' "${WORKDIR}/fdt@1.dts" > "${WORKDIR}/fdt@1.dts.patched"
	"$DTC" -I dts -O dtb -o "${WORKDIR}/fdt@1" "${WORKDIR}/fdt@1.dts.patched"
}

bundle_installer() {
	unfit_image "$@"
	extract_initrd
	cp -avr "${INSTALLERDIR}/files/"* "${WORKDIR}/initrd"
	repack_initrd
	allow_mtd_write
	cd "${WORKDIR}"
	refit_image 128k
}

linksys_e8450_installer() {
	build_openwrt
	BINDIR="${OPENWRT_DIR}/bin/targets/mediatek/mt7622"
	[ -d "$BINDIR" ] || exit 1

	cp -v "${BINDIR}/openwrt-mediatek-mt7622-linksys_e8450-ubi-preloader.bin" "${INSTALLERDIR}/files/installer"
	cp -v "${BINDIR}/openwrt-mediatek-mt7622-linksys_e8450-ubi-bl31-uboot.fip" "${INSTALLERDIR}/files/installer"
	cp -v "${BINDIR}/openwrt-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery.fit" "${INSTALLERDIR}/files/installer"
	cp -v "${BINDIR}/openwrt-mediatek-mt7622-linksys_e8450-ubi-squashfs-sysupgrade.fit" "${DESTDIR}"

	bundle_installer "${BINDIR}/openwrt-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery.fit"

	mv "${WORKDIR}/${FILEBASE}-installer.fit" "${DESTDIR}"
	rm -r "${WORKDIR}"
}

linksys_e8450_installer
