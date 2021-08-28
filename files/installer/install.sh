#!/bin/sh

. /lib/upgrade/nand.sh

sleep 1

echo
echo OpenWrt UBI installer
echo

INSTALLER_DIR="/installer"
PRELOADER="$INSTALLER_DIR/openwrt-mediatek-mt7622-linksys_e8450-ubi-preloader.bin"
FIP="$INSTALLER_DIR/openwrt-mediatek-mt7622-linksys_e8450-ubi-bl31-uboot.fip"
RECOVERY="$INSTALLER_DIR/openwrt-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery.itb"
FIT="$INSTALLER_DIR/openwrt-mediatek-mt7622-linksys_e8450-ubi-squashfs-sysupgrade.itb"
HAS_ENV=1


install_fix_factory() {
	local mtddev=$1
	local assertm=$2
	local ebs=$(cat /sys/class/mtd/$(basename $mtddev)/erasesize)
	local off=0
	local skip=0
	local found

	while [ $((off)) -lt $((2 * ebs)) ]; do
		magic="$(hexdump -v -s $off -n 2 -e '"%02x"' $1)"
		if [ "$magic" = "$assertm" ]; then
			found=1
			break
		fi
		off=$((off + ebs))
		skip=$((skip + 1))
	done

	if ! [ "$found" = "1" ]; then
		echo "factory partition not found anywhere, aborting"
		exit 1
	fi

	echo -n "found factory partition at offset $(printf %08x $((off))), rewriting..."

	dd if=$mtddev bs=$ebs skip=$skip count=1 of=/tmp/factory-fixed
	mtd write /tmp/factory-fixed $mtddev
	local magic="$(hexdump -v -n 2 -e '"%02x"' $mtddev)"
	[ "$magic" = "$assertm" ] || exit 1
}

install_fix_macpart() {
	local mtddev=$1
	local blockoff=$2
	local macoff=$3
	local destoff=$blockoff
	local ebs=$(cat /sys/class/mtd/$(basename $mtddev)/erasesize)
	local skip=$((blockoff / ebs))
	local readp1 readp2
	local found

	while [ $((blockoff)) -le $((destoff + (2 * ebs))) ]; do
		readm1=$(hexdump -s $((blockoff + macoff)) -v -n 6 -e '6/1 "%02x"' /dev/mtd2)
		readm2=$(hexdump -s $((blockoff + macoff + 6)) -v -n 6 -e '6/1 "%02x"' /dev/mtd2)
		# that doesn't look valid to beging with...
		if [ "${readm1:0:6}" = "000000" ] ||
		   [ "${readm1:0:2}" = "f0" ] ||
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
		skip=$((skip + 1))
		blockoff=$((blockoff + ebs))
	done

	if ! [ "$found" = "1" ]; then
		echo "mac addresses not found anywhere in factory partition, aborting"
		exit 1
	fi

	[ $((blockoff)) -eq $((destoff)) ] ||
		echo "mac addresses block shifted by 0x$(printf %08x $((blockoff - destoff))), fixing."

	dd if=$mtddev bs=$ebs skip=$skip count=1 of=/tmp/macs-fixed
	mtd -p $destoff -l $ebs write /tmp/macs-fixed $mtddev
}

install_prepare_backup() {
	echo "preparing backup of relevant flash areas..."
	mkdir /tmp/backup
	for mtdnum in $(seq 0 $1); do
		local ebs=$(cat /sys/class/mtd/mtd${mtdnum}/erasesize)
		dd bs=$ebs if=/dev/mtd${mtdnum} of=/tmp/backup/mtd${mtdnum}
	done
}

install_write_backup() {
	echo "writing backup files to ubi volume..."
	ubimkvol /dev/ubi0 -s 8MiB -n 3 -N boot_backup
	mount -t ubifs /dev/$(nand_find_volume ubi0 boot_backup) /mnt
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
	[ -e /sys/class/ubi/ubi0 ] || exit 1
	devminormajor=$(cat /sys/class/ubi/ubi0/dev)
	oIFS=$IFS
	IFS=':'
	set -- $devminormajor
	devminor=$1
	devmajor=$2
	IFS=$oIFS
	[ -e /dev/ubi0 ] || mknod /dev/ubi0 c $devminor $devmajor
	[ "$HAS_ENV" = "1" ] && ubimkvol /dev/ubi0 -n 0 -s 1MiB -N ubootenv && ubimkvol /dev/ubi0 -n 1 -s 1MiB -N ubootenv2
}

# Linksys E8450 got factory data in /dev/mtd2
# things may be shifted due to MTK BMT/BBT being used previously, fix that

# backup mtd0...mtd2
install_prepare_backup 2

# rewrite two mac addresses are stored at correct offset in factory partition
install_fix_macpart /dev/mtd2 0x60000 0x1fff4

# make sure wifi eeprom starts at correct offset and rewrite to fix ECC
install_fix_factory /dev/mtd2 "7622"

echo "redundantly write bl2 into the first 4 blocks"
for bl2start in 0x0 0x20000 0x40000 0x60000 ; do
	mtd -p $bl2start write $PRELOADER /dev/mtd0
done

echo "write FIP to NAND"
mtd write $FIP /dev/mtd1

install_prepare_ubi /dev/mtd3

echo "write recovery ubi volume"
RECOVERY_SIZE=$(cat $RECOVERY | wc -c)
ubimkvol /dev/ubi0 -s $RECOVERY_SIZE -n 2 -N recovery
ubiupdatevol /dev/$(nand_find_volume ubi0 recovery) $RECOVERY

install_write_backup

sync

sleep 5

reboot -f
