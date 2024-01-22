#!/bin/sh

. /lib/upgrade/nand.sh

sleep 1

echo
echo OpenWrt UBI installer
echo

INSTALLER_DIR="/installer"
PRELOADER="$INSTALLER_DIR/mt7622-snand-ubi-1ddr-bl2.img"
FIP="$INSTALLER_DIR/mt7622_linksys_e8450-u-boot.fip"
RECOVERY="$(ls -1 $INSTALLER_DIR/openwrt-*mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery.itb)"
HAS_ENV=1
HAS_FIP=1
HAS_FACTORY=1

if [ ! -s "$PRELOADER" ] || [ ! -s "$FIP" ] || [ ! -s "$RECOVERY" ]; then
	echo "Missing files. Aborting."
	reboot
	exit 1
fi

ubi_mknod() {
	local dev="$1"
	dev="${dev##*/}"
	[ -e "/sys/class/ubi/$dev/uevent" ] || return 2
	source "/sys/class/ubi/$dev/uevent"
	mknod "/dev/$dev" c $MAJOR $MINOR
}

install_get_factory() {
	local mtddev="$1"
	local ebs=$(cat /sys/class/mtd/$(basename $mtddev)/erasesize)
	local assertm="$3"
	local init_off="$2"
	local off=$init_off
	local skip="$((init_off / ebs))"
	local found

	while [ $((off)) -lt $((init_off + 4 * ebs)) ]; do
		magic="$(hexdump -v -s $off -n 2 -e '"%02x"' $1)"
		if [ "$magic" = "$assertm" ]; then
			found=1
			break
		fi
		off=$((off + ebs))
		skip=$((skip + 1))
	done

	if [ "$found" != "1" ]; then
		echo "factory partition not found on raw flash offset"
		return 1
	fi

	echo -n "found factory partition at offset $(printf %08x $((off)))"

	dd if=$mtddev bs=$ebs skip=$skip count=1 of=/tmp/eeproms
}

install_get_macblock() {
	local mtddev=$1
	local blockoff=$2
	local macoff=$3
	local destoff=$blockoff
	local ebs=$(cat /sys/class/mtd/$(basename $mtddev)/erasesize)
	local skip=$((blockoff / ebs))
	local readp1 readp2
	local found

	while [ $((blockoff)) -le $((destoff + (2 * ebs))) ]; do
		readm1=$(hexdump -s $((blockoff + macoff)) -v -n 6 -e '6/1 "%02x"' "$1")
		readm2=$(hexdump -s $((blockoff + macoff + 6)) -v -n 6 -e '6/1 "%02x"' "$1")
		# that doesn't look valid to beging with...
		if [ "${readm1:0:6}" = "000000" ] ||
		   [ "${readm1:0:2}" = "f0" ] ||
		   [ "${readm1:0:2}" = "ff" ] ||
		   [ "$((((0x${readm1:0:2})>>2)<<2))" != "$((0x${readm1:0:2}))" ]; then
			blockoff=$((blockoff + ebs))
			skip=$((skip + 1))
			continue
		fi
		# could be valid and contains two identical 3-bytes prefixes
		if [ "${readm1:0:6}" = "${readm2:0:6}" ]; then
			echo -n "Found MAC addresses block"
			echo -n " LAN: ${readm1:0:2}:${readm1:2:2}:${readm1:4:2}:${readm1:6:2}:${readm1:8:2}:${readm1:10:2}"
			echo    " WAN: ${readm2:0:2}:${readm2:2:2}:${readm2:4:2}:${readm2:6:2}:${readm2:8:2}:${readm2:10:2}"
			found=1
			break
		fi
		blockoff=$((blockoff + ebs))
		skip=$((skip + 1))
	done

	if ! [ "$found" = "1" ]; then
		echo "mac addresses not found anywhere in factory partition, aborting"
		return 1
	fi

	[ $((blockoff)) -eq $((destoff)) ] ||
		echo "mac addresses block shifted by 0x$(printf %08x $((blockoff - destoff)))!."

	dd if=$mtddev bs=$ebs skip=$skip count=1 of=/tmp/macs
}

install_prepare_backup() {
	echo "preparing backup of relevant flash areas..."
	mkdir /tmp/backup
	for mtdnum in $(seq 0 $1); do
		local ebs=$(cat /sys/class/mtd/mtd${mtdnum}/erasesize)
		dd bs=$ebs if=/dev/mtd${mtdnum} of=/tmp/backup/mtd${mtdnum} ${2:+count=$2}
	done
}

install_write_backup() {
	echo "writing backup files to ubi volume..."
	ubimkvol /dev/ubi0 -n 6 -s 8MiB -N boot_backup
	ubi_mknod ubi0_6
	mount -t ubifs /dev/ubi0_6 /mnt
	cp /tmp/backup/mtd* /mnt
	umount /mnt
}

install_prepare_ubi() {
	mtddev=$1
	[ -e /sys/class/ubi/ubi0 ] && ubidetach -p $mtddev
	ubiformat -y $mtddev
	sleep 1
	ubiattach -p $mtddev
	sync
	sleep 1
	[ -e /dev/ubi0 ] || ubi_mknod ubi0
	[ "$HAS_FIP" = "1" ] && ubimkvol /dev/ubi0 -n 0 -t static -s $(cat $FIP | wc -c) -N fip && ubi_mknod ubi0_0 && ubiupdatevol /dev/ubi0_0 "$FIP"
	[ "$HAS_FACTORY" = "1" ] && ubimkvol /dev/ubi0 -n 1 -t static -s $(cat "/tmp/factory" | wc -c) -N factory && ubi_mknod ubi0_1 && ubiupdatevol /dev/ubi0_1 "/tmp/factory"
	[ "$HAS_ENV" = "1" ] && ubimkvol /dev/ubi0 -n 2 -s 126976 -N ubootenv && ubimkvol /dev/ubi0 -n 3 -s 126976 -N ubootenv2
}

# backup mtd0...mtd1, max. 32x 128kb block
install_prepare_backup 1 32

# Linksys E8450 got factory data stored in MTD partition Factory at 0x1c0000
# things may be shifted due to MTK BMT/BBT being used previously, take that
# into account while extracting

# extract wifi eeprom from Factory MTD partition
install_get_factory /dev/mtd1 0x140000 "7622" || exit 1

# two mac addresses are stored in Factory partition
install_get_macblock /dev/mtd1 0x1a0000 0x1fff4 || exit 1

# assemble factory blob
dd if=/dev/full of=/tmp/factory bs=524288 count=1
dd if=/tmp/eeproms of=/tmp/factory conv=notrunc
dd if=/tmp/macs of=/tmp/factory bs=131072 seek=3 count=1

echo "redundantly write bl2 into the first 4 blocks"
for bl2start in 0x0 0x20000 0x40000 0x60000 ; do
	mtd -p $bl2start write $PRELOADER /dev/mtd0
done

install_prepare_ubi /dev/mtd1

echo "write recovery ubi volume"
RECOVERY_SIZE=$(cat $RECOVERY | wc -c)
ubimkvol /dev/ubi0 -n 4 -s $RECOVERY_SIZE -N recovery
ubi_mknod ubi0_4
ubiupdatevol /dev/ubi0_4 $RECOVERY
ubimkvol /dev/ubi0 -n 5 -s 126976 -N fit

install_write_backup

sync

sleep 5

reboot -f
