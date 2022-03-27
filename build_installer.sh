#!/bin/bash -x

DESTDIR="$PWD"

OPENWRT_PGP="0xCD84BCED626471F1"
KEYSERVER="keyserver.ubuntu.com"
INSTALLERDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
OPENWRT_DIR="${INSTALLERDIR}/openwrt-ib"

CPIO="${OPENWRT_DIR}/staging_dir/host/bin/cpio"
MKIMAGE="${OPENWRT_DIR}/staging_dir/host/bin/mkimage"
OPKG="${OPENWRT_DIR}/staging_dir/host/bin/opkg"
XZ="${OPENWRT_DIR}/staging_dir/host/bin/xz"

UNFIT="${INSTALLERDIR}/unfit"
[ -x "$UNFIT" ] || ( cd "${INSTALLERDIR}/src" ; cmake . ; make all ; cp unfit .. ) || {
	echo "can't build unfit. please install gcc and libfdt-dev"
	exit 0
}

SOURCE_DATE_EPOCH=$(git log -1 --pretty=%ct -C "${INSTALLERDIR}")
DTC=
FILEBASE=
WORKDIR=
ITSFILE=

run_openwrt_ib() {
	mkdir -p "${INSTALLERDIR}/dl"
	cd "${INSTALLERDIR}/dl"
	gpg --no-default-keyring--keyring "${INSTALLERDIR}/openwrt-keyring" --list-key $OPENWRT_PGP 1>/dev/null 2>/dev/null || gpg --no-default-keyring --keyring "${INSTALLERDIR}/openwrt-keyring" --keyserver ${KEYSERVER}  --recv-key $OPENWRT_PGP
	gpg --no-default-keyring --keyring "${INSTALLERDIR}/openwrt-keyring" --list-key $OPENWRT_PGP 1>/dev/null 2>/dev/null || exit 0
	rm "sha256sums.asc" "sha256sums"
	wget "${OPENWRT_TARGET}/sha256sums.asc"
	wget "${OPENWRT_TARGET}/sha256sums"
	gpg --no-default-keyring --keyring "${INSTALLERDIR}/openwrt-keyring" --verify sha256sums.asc sha256sums || exit 1
	sha256sum -c sha256sums --ignore-missing || rm -f  "$OPENWRT_INITRD" "$OPENWRT_IB"
	wget -c "${OPENWRT_TARGET}/${OPENWRT_INITRD}"
	wget -c "${OPENWRT_TARGET}/${OPENWRT_IB}"
	sha256sum -c sha256sums --ignore-missing || exit 1
	mkdir -p "${OPENWRT_DIR}" || exit 1
	tar -xJf "${INSTALLERDIR}/dl/${OPENWRT_IB}" -C "${OPENWRT_DIR}" --strip-components=1
	DTC="$(ls -1 ${OPENWRT_DIR}/build_dir/target-aarch64_cortex-a53_musl/linux-mediatek_mt7622/linux-*/scripts/dtc/dtc)"
	[ -x "$DTC" ] || {
		echo "can't find dtc executable in OpenWrt IB"
		exit 1
	}
	cd $OPENWRT_DIR
	sed -i 's/CONFIG_SIGNATURE_CHECK=y/# CONFIG_SIGNATURE_CHECK is not set/' .config
	make image PROFILE=linksys_e8450-ubi PACKAGES="$OPENWRT_UPG_PACKAGES"
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
	FILEBASE="$(basename "$INFILE" .itb)"
	WORKDIR="$(mktemp -d)"
	ITSFILE="${WORKDIR}/image.its"
	mkdir -p "$WORKDIR"
	cd "$WORKDIR"
	"$UNFIT" "$INFILE"

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
	imgtype=$2
	# re-add data nodes from files
	its_add_data > "${ITSFILE}.new"

	MKIMAGE_PARM=""
	[ "$EXTERNAL" = "1" ] && MKIMAGE_PARM="$MKIMAGE_PARM -E -B 0x1000"
	[ "$STATIC" = "1" ] && MKIMAGE_PARM="$MKIMAGE_PARM -p 0x1000"

	PATH="$PATH:$(dirname "$DTC")" "$MKIMAGE" $MKIMAGE_PARM -f "${ITSFILE}.new" "${FILEBASE}-refit.itb"

	dd if="${FILEBASE}-refit.itb" of="${FILEBASE}${imgtype:+-$imgtype}.itb" bs=$1 conv=sync
}

extract_initrd() {
	[ -e "${WORKDIR}/initrd-1" ] || return 1
	[ -e "${WORKDIR}/initrd" ] && rm -rf "${WORKDIR}/initrd"
	mkdir "${WORKDIR}/initrd"
	"${XZ}" -d < "${WORKDIR}/initrd-1" | "${CPIO}" -i -D "${WORKDIR}/initrd"
	rm "${WORKDIR}/initrd-1"
	echo "initrd extracted in '${WORKDIR}/initrd'"
	return 0
}

repack_initrd() {
	[ -d "${WORKDIR}/initrd" ] || return 1
	find "${WORKDIR}/initrd" -newermt "@${SOURCE_DATE_EPOCH}" -print0 |
		xargs -0r touch --no-dereference --date="@${SOURCE_DATE_EPOCH}"
	echo "re-compressing initrd..."
	( cd "${WORKDIR}/initrd" ; find . | LC_ALL=C sort | "${CPIO}" --reproducible -o -H newc -R 0:0 | "${XZ}" -T0 -c -9  --check=crc32 > "${WORKDIR}/initrd-1" )
	return 0
}

allow_mtd_write() {
	"$DTC" -I dtb -O dts -o "${WORKDIR}/fdt-1.dts" "${WORKDIR}/fdt-1"
	rm "${WORKDIR}/fdt-1"
	grep -v 'read-only' "${WORKDIR}/fdt-1.dts" > "${WORKDIR}/fdt-1.dts.patched"
	"$DTC" -I dts -O dtb -o "${WORKDIR}/fdt-1" "${WORKDIR}/fdt-1.dts.patched"
}

enable_services() {
	cd ${WORKDIR}/initrd
	for service in ./etc/init.d/*; do
		( cd ${WORKDIR}/initrd ; IPKG_INSTROOT="${WORKDIR}/initrd" $(command -v bash) ./etc/rc.common $service enable 2>/dev/null )
	done
}

bundle_initrd() {
	local imgtype=$1
	shift

	unfit_image "$1"
	shift

	extract_initrd

	[ "${OPENWRT_REMOVE_PACKAGES}" ] && IPKG_NO_SCRIPT=1 IPKG_INSTROOT="${WORKDIR}/initrd" \
		"${OPKG}" --offline-root="${WORKDIR}/initrd" -f "${WORKDIR}/initrd/etc/opkg.conf" \
		remove ${OPENWRT_REMOVE_PACKAGES}

	PATH="$(dirname "${OPKG}"):$PATH" \
	OPKG_KEYS="${WORKDIR}/initrd/etc/opkg/keys" \
	TMPDIR="${WORKDIR}/initrd/tmp" \
		"${OPKG}" --offline-root="${WORKDIR}/initrd" -f "${WORKDIR}/initrd/etc/opkg.conf" \
			--verify-program="${WORKDIR}/initrd/usr/sbin/opkg-key" \
			update

	[ "${OPENWRT_ADD_PACKAGES}" ] && \
		PATH="$(dirname "${OPKG}"):$PATH" \
		OPKG_KEYS="${WORKDIR}/initrd/etc/opkg/keys" \
		TMPDIR="${WORKDIR}/initrd/tmp" \
		IPKG_NO_SCRIPT=1 IPKG_INSTROOT="${WORKDIR}/initrd" \
		"${OPKG}" --offline-root="${WORKDIR}/initrd" -f "${WORKDIR}/initrd/etc/opkg.conf" \
		--verify-program="${WORKDIR}/initrd/usr/sbin/opkg-key" \
		--force-postinst install ${OPENWRT_ADD_PACKAGES}

	case "$imgtype" in
		recovery)
			PATH="$(dirname "${OPKG}"):$PATH" \
			OPKG_KEYS="${WORKDIR}/initrd/etc/opkg/keys" \
			TMPDIR="${WORKDIR}/initrd/tmp" \
			IPKG_NO_SCRIPT=1 IPKG_INSTROOT="${WORKDIR}/initrd" \
				"${OPKG}" --offline-root="${WORKDIR}/initrd" -f "${WORKDIR}/initrd/etc/opkg.conf" \
				--verify-program="${WORKDIR}/initrd/usr/sbin/opkg-key" \
				--force-postinst install ${OPENWRT_ADD_REC_PACKAGES}
			;;
		installer)
			cp -avr "${INSTALLERDIR}/files/"* "${WORKDIR}/initrd"
			cp -v "$@" "${WORKDIR}/initrd/installer"
			;;
	esac

	enable_services
	rm -rf "${WORKDIR}/initrd/tmp/"*

	repack_initrd

	cd "${WORKDIR}"
	case "$imgtype" in
		recovery)
			refit_image 128k
			;;
		installer)
			allow_mtd_write
			refit_image 128k $imgtype
			;;
	esac
}

linksys_e8450_installer() {
	OPENWRT_TARGET="https://downloads.openwrt.org/snapshots/targets/mediatek/mt7622"
	OPENWRT_IB="openwrt-imagebuilder-mediatek-mt7622.Linux-x86_64.tar.xz"
	OPENWRT_INITRD="openwrt-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery.itb"
	OPENWRT_REMOVE_PACKAGES="wpad-basic-wolfssl libustream-wolfssl* libwolfssl* px5g-wolfssl"
	OPENWRT_ADD_PACKAGES=""
	OPENWRT_ADD_REC_PACKAGES="wpad-openssl libustream-openssl luci luci-ssl-openssl luci-theme-openwrt-2020 kmod-mtd-rw"
	OPENWRT_ENABLE_SERVICE="uhttpd wpad"

	OPENWRT_UPG_PACKAGES="auc blockd kmod-usb-storage kmod-usb-storage-uas kmod-fs-vfat \
				kmod-nls-base kmod-nls-cp437 kmod-nls-iso8859-1 kmod-nls-utf8 \
				kmod-fs-ext4 kmod-fs-f2fs kmod-fs-exfat \
				luci luci-ssl-openssl luci-theme-openwrt-2020 luci-app-attendedsysupgrade \
				-libustream-wolfssl -wpad-basic-wolfssl -px5g-wolfssl libustream-openssl wpad-openssl \
				$OPENWRT_ADD_PACKAGES"

	run_openwrt_ib
	BINDIR="${OPENWRT_DIR}/bin/targets/mediatek/mt7622"
	[ -d "$BINDIR" ] || exit 1

	mv "${BINDIR}/openwrt-mediatek-mt7622-linksys_e8450-ubi-squashfs-sysupgrade.itb" "${DESTDIR}"

	bundle_initrd recovery "${INSTALLERDIR}/dl/${OPENWRT_INITRD}"

	mv "${WORKDIR}/${FILEBASE}.itb" "${DESTDIR}"
	rm -r "${WORKDIR}"


	bundle_initrd installer "${INSTALLERDIR}/dl/${OPENWRT_INITRD}" \
		"${BINDIR}/openwrt-mediatek-mt7622-linksys_e8450-ubi-preloader.bin" \
		"${BINDIR}/openwrt-mediatek-mt7622-linksys_e8450-ubi-bl31-uboot.fip" \
		"${DESTDIR}/${FILEBASE}.itb"

	mv "${WORKDIR}/${FILEBASE}-installer.itb" "${DESTDIR}"
	rm -r "${WORKDIR}"
}

linksys_e8450_installer
