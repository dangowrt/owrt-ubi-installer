#!/bin/bash -x
set -o errexit
set -o nounset
set -o pipefail

DESTDIR="$PWD"

OPENWRT_PGP="0x1D53D1877742E911"
KEYSERVER="keyserver.ubuntu.com"
INSTALLERDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
OPENWRT_DIR="${INSTALLERDIR}/openwrt-ib"

CPIO="${OPENWRT_DIR}/staging_dir/host/bin/cpio"
MKIMAGE="${OPENWRT_DIR}/staging_dir/host/bin/mkimage"
APK="${OPENWRT_DIR}/staging_dir/host/bin/apk"
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


prepare_openwrt_ib() {
	GNUPGHOME="$(mktemp -d)"
	export GNUPGHOME
	trap 'rm -rf -- "${GNUPGHOME}"' EXIT

	mkdir -p "${INSTALLERDIR}/dl"
	cd "${INSTALLERDIR}/dl"
	gpg --no-default-keyring --keyring "${INSTALLERDIR}/openwrt-keyring" --list-key $OPENWRT_PGP 1>/dev/null 2>/dev/null || gpg --no-default-keyring --keyring "${INSTALLERDIR}/openwrt-keyring" --keyserver ${KEYSERVER}	--recv-key $OPENWRT_PGP
	gpg --no-default-keyring --keyring "${INSTALLERDIR}/openwrt-keyring" --list-key $OPENWRT_PGP 1>/dev/null 2>/dev/null || exit 0
	rm -f "sha256sums.asc" "sha256sums"
	wget "${OPENWRT_TARGET}/sha256sums.asc"
	wget "${OPENWRT_TARGET}/sha256sums"
	gpg --no-default-keyring --keyring "${INSTALLERDIR}/openwrt-keyring" --verify sha256sums.asc sha256sums || exit 1

	trap - EXIT
	rm -rf -- "${GNUPGHOME}"
	export -n GNUPGHOME

	sha256sum -c sha256sums --ignore-missing || rm -f "$OPENWRT_SYSUPGRADE" "$OPENWRT_IB" "$OPENWRT_INITRD"
	wget -c "${OPENWRT_TARGET}/${OPENWRT_INITRD}"
	wget -c "${OPENWRT_TARGET}/${OPENWRT_SYSUPGRADE}"
	wget -c "${OPENWRT_TARGET}/${OPENWRT_IB}"
	sha256sum -c sha256sums --ignore-missing || exit 1
	mkdir -p "${OPENWRT_DIR}" || exit 1
	tar -xf "${INSTALLERDIR}/dl/${OPENWRT_IB}" -C "${OPENWRT_DIR}" --strip-components=1
	DTC="$(ls -1 "${OPENWRT_DIR}/build_dir/target-aarch64_cortex-a53_musl/linux-mediatek_filogic/linux-"*"/scripts/dtc/dtc")"
	[ -x "$DTC" ] || {
		echo "can't find dtc executable in OpenWrt IB"
		exit 1
	}
}

its_add_data() {
	local line
	local in_images=0
	local in_image=0
	local br_level=0
	local img_name
	while read -r line; do
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
	done < "${ITSFILE}"
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

	# figure out exact FIT image type
	EXTERNAL=
	STATIC=
	grep -q "data-size = " "$ITSFILE" && EXTERNAL=1
	grep -q "data-position = " "$ITSFILE" && STATIC=1

	# filter-out existing data nodes
	grep -v -e "data = " -e "data-size = " -e "data-offset = " -e "data-position = " "$ITSFILE" > "${ITSFILE}.new"
	mv "${ITSFILE}.new" "${ITSFILE}"
}

refit_image() {
	local blocksize="${1}"
	local imgtype
	[ -n "${2-}" ] && imgtype="${2}"
	local MKIMAGE_PARM=()

	# re-add data nodes from files
	its_add_data > "${ITSFILE}.new"

	[ "$EXTERNAL" = "1" ] && MKIMAGE_PARM=("${MKIMAGE_PARM[@]}" -E -B 0x1000)
	[ "$STATIC" = "1" ] && MKIMAGE_PARM=("${MKIMAGE_PARM[@]}" -p 0x1000)

	PATH="$PATH:$(dirname "$DTC")" \
		SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH \
		"$MKIMAGE" "${MKIMAGE_PARM[@]}" -f "${ITSFILE}.new" "${FILEBASE}-refit.itb"

	echo "imgtype: \"${imgtype:-(unset)}\""
	dd if="${FILEBASE}-refit.itb" of="${FILEBASE}${imgtype:+-$imgtype}.itb" bs="$blocksize" conv=sync
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
	grep -v 'linux,ubi' "${WORKDIR}/fdt-1.dts.patched" > "${WORKDIR}/fdt-1.dts.patched2"
	mv "${WORKDIR}/fdt-1.dts.patched2" "${WORKDIR}/fdt-1.dts.patched"
	sed -i 's/"ubi"/"newubi"/' "${WORKDIR}/fdt-1.dts.patched"
	sed -i 's/"spi-nand"/"u-boot-dont-touch-spi-nand"/' "${WORKDIR}/fdt-1.dts.patched"
	sed -i 's/partitions {/mtdparts: partitions {/' "${WORKDIR}/fdt-1.dts.patched"
	cat >>"${WORKDIR}/fdt-1.dts.patched" <<EOF

&mtdparts {
	partition@400000 {
		reg = <0x400000 0x7c00000>;
		label = "OLD_UBI_DEV";
	};
};
EOF
	"$DTC" -I dts -O dtb -o "${WORKDIR}/fdt-1" "${WORKDIR}/fdt-1.dts.patched"
}

enable_services() {
	cd "${WORKDIR}/initrd"
	for service in ./etc/init.d/*; do
		( cd "${WORKDIR}/initrd" ; IPKG_INSTROOT="${WORKDIR}/initrd" $(command -v bash) ./etc/rc.common "$service" enable 2>/dev/null )
	done
}

bundle_initrd() {
	local imgtype=$1
	shift

	unfit_image "$1"
	shift

	extract_initrd

	[[ ${#OPENWRT_REMOVE_PACKAGES[@]} -gt 0 ]] && IPKG_NO_SCRIPT=1 IPKG_INSTROOT="${WORKDIR}/initrd" \
		"${APK}" --no-scripts --no-logfile --root "${WORKDIR}/initrd" del "${OPENWRT_REMOVE_PACKAGES[@]}"

	PATH="$(dirname "${APK}"):$PATH" \
	TMPDIR="${WORKDIR}/initrd/tmp" \
		"${APK}" --no-logfile --root "${WORKDIR}/initrd" update

	[[ ${#OPENWRT_ADD_PACKAGES[@]} -gt 0 ]] && \
		PATH="$(dirname "${APK}"):$PATH" \
		TMPDIR="${WORKDIR}/initrd/tmp" \
		IPKG_NO_SCRIPT=1 IPKG_INSTROOT="${WORKDIR}/initrd" \
		"${APK}" --no-scripts --no-logfile --root "${WORKDIR}/initrd" add "${OPENWRT_ADD_PACKAGES[@]}"

	case "$imgtype" in
		recovery)
			[[ ${#OPENWRT_ADD_REC_PACKAGES[@]} -gt 0 ]] && \
			PATH="$(dirname "${APK}"):$PATH" \
			TMPDIR="${WORKDIR}/initrd/tmp" \
			IPKG_NO_SCRIPT=1 IPKG_INSTROOT="${WORKDIR}/initrd" \
				"${APK}" --no-scripts --no-logfile --root "${WORKDIR}/initrd" add "${OPENWRT_ADD_REC_PACKAGES[@]}"
			;;
		installer)
			cp -avr "${INSTALLERDIR}/files/"* "${WORKDIR}/initrd"
			cp -v "$@" "${WORKDIR}/initrd/installer"
			;;
	esac

	enable_services
	rm -rf "${WORKDIR}/initrd/tmp/"*

	find ${WORKDIR}/initrd/ -mindepth 1 -execdir touch -hcd "@${SOURCE_DATE_EPOCH}" "{}" +

	repack_initrd

	cd "${WORKDIR}"
	case "$imgtype" in
		recovery)
			refit_image 128k
			;;
		installer)
			allow_mtd_write
			EXTERNAL=
			STATIC=
			sed -i 's/<0x46000000>/<0x48080000>/' "${ITSFILE}"
			refit_image 128k "$imgtype"
			;;
	esac
}

asus_bt8_installer() {
	OPENWRT_TARGET="https://downloads.openwrt.org/snapshots/targets/mediatek/filogic"
	OPENWRT_IB="openwrt-imagebuilder-mediatek-filogic.Linux-x86_64.tar.zst"
	OPENWRT_INITRD="openwrt-mediatek-filogic-asus_zenwifi-bt8-initramfs-recovery.itb"
	OPENWRT_SYSUPGRADE="openwrt-mediatek-filogic-asus_zenwifi-bt8-squashfs-sysupgrade.itb"
	OPENWRT_ADD_REC_PACKAGES=(uhttpd luci-mod-admin-full luci-theme-bootstrap)
	OPENWRT_REMOVE_PACKAGES=(kmod-mt7996-firmware kmod-mt7996e kmod-mt76-connac kmod-mt76-core kmod-mt7996-firmware mt7988-wo-firmware odhcp6c odhcpd-ipv6only ppp ppp-mod-pppoe wpad-basic-mbedtls)
	OPENWRT_ADD_PACKAGES=()

	prepare_openwrt_ib

	make -C ${OPENWRT_DIR} info | grep "Default Packages:" | grep -q fitblk || {
		echo "ImageBuilder is outdated and not in sync with installer."
		echo "Please re-run once fitblk changes are included in snapshot build."
		exit 1
	}

	bundle_initrd recovery "${INSTALLERDIR}/dl/${OPENWRT_INITRD}"

	mv "${WORKDIR}/${FILEBASE}.itb" "${DESTDIR}"
	rm -r "${WORKDIR}"
	cp "${INSTALLERDIR}/dl/${OPENWRT_SYSUPGRADE}" "${DESTDIR}"

	bundle_initrd installer "${INSTALLERDIR}/dl/${OPENWRT_INITRD}" \
		"${OPENWRT_DIR}/staging_dir/target-aarch64_cortex-a53_musl/image/mt7988-spim-nand-ubi-ddr4-bl2.img" \
		"${OPENWRT_DIR}/staging_dir/target-aarch64_cortex-a53_musl/image/mt7988_asus_zenwifi-bt8-u-boot.fip" \
		"${DESTDIR}/${FILEBASE}.itb"

	${MKIMAGE} -A arm64 -O linux -T kernel -C lzma -a 0x48080000 -e 0x48080000 -d "${WORKDIR}/${FILEBASE}-installer"* "${DESTDIR}/${FILEBASE}-installer.trx"
	rm -r "${WORKDIR}"
}

asus_bt8_installer
