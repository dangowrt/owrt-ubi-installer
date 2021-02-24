#!/bin/sh

. /lib/upgrade/nand.sh

echo
echo OpenWrt UBI installer
echo

INSTALLER_DIR="/installer"
PRELOADER="$INSTALLER_DIR/openwrt-mediatek-mt7622-linksys_e8450-ubi-preloader.bin"
FIP="$INSTALLER_DIR/openwrt-mediatek-mt7622-linksys_e8450-ubi-bl31-uboot.fip"
RECOVERY="$INSTALLER_DIR/openwrt-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery.fit"
FIT="$INSTALLER_DIR/openwrt-mediatek-mt7622-linksys_e8450-ubi-squashfs-sysupgrade.fit"
HAS_ENV=1


install_fix_factory() {
	local mtddev=$1
	local ebs=$(cat /sys/class/mtd/$(basename $mtddev)/erasesize)
	local off=0
	local found

	while [ $((off)) -lt $((2 * ebs)) ]; do
		magic="$(hexdump -v -s $off -n 2 -e '"%02x"' $1)"
		[ "$magic" = "7622" ] && {
			found=1
			break;
		}
		off=$((off + ebs))
	done

	if ! [ "$found" = "1" ]; then
		echo "factory partition not found anywhere, aborting"
		exit 1
	fi

	echo "found factory partition at offset $off, fixing."
	nanddump -l $ebs -f /tmp/factory -s $off $mtddev
	nandwrite -m -s 0 $mtddev /tmp/factory
}

install_fix_macpart() {
	local mtddev=$1
	local blockoff=$2
	local macoff=$3
	local destoff=$blockoff
	local ebs=$(cat /sys/class/mtd/$(basename $mtddev)/erasesize)
	local readp1 readp2
	local found

	while [ $((blockoff)) -le $((destoff + (2 * ebs))) ]; do
		readp1=$(hexdump -s $((blockoff + macoff)) -v -n 3 -e '3/1 "%02x"' /dev/mtd2)
		readp2=$(hexdump -s $((blockoff + macoff + 6)) -v -n 3 -e '3/1 "%02x"' /dev/mtd2)
		if [ "$readp1" = "ffffff" -o "$readp1" = "000000" ]; then
			blockoff=$((blockoff + ebs))
			continue
		fi
		# non empty and contains two something which looks like it
		if [ "$readp1" = "$readp2" ]; then
			found=1
			break
		fi
		blockoff=$((blockoff + ebs))
	done

	if ! [ "$found" = "1" ]; then
		echo "mac addresses not found anywhere in factory partition, aborting"
		exit 1
	fi

	[ $((blockoff)) -eq $((destoff)) ] && return

	echo "found mac addresses shifted by 0x$(printf %08x $((blockoff - destoff))), fixing."
	nanddump -l $ebs -f /tmp/macaddrs -s $blockoff $mtddev
	nandwrite -m $mtddev -s $destoff /tmp/macaddrs
}

install_prepare_backup() {
	echo "preparing backup of relevant flash areas..."
	mkdir /tmp/backup
	nanddump -n -o -f /tmp/backup/mtd0.oob /dev/mtd0
	nanddump -n -o -f /tmp/backup/mtd1.oob /dev/mtd1
	nanddump -n -o -f /tmp/backup/mtd2.oob /dev/mtd2
}

install_write_backup() {
	echo "writing backup files to ubi volume..."
	ubimkvol /dev/ubi0 -s 8MiB -n 3 -N boot_backup
	mount -t ubifs /dev/$(nand_find_volume ubi0 boot_backup) /mnt
	cp /tmp/backup/mtd* /mnt
	umount /mnt
}

install_prepare_ubi() {
	ubiformat -y /dev/mtd3
	ubiattach -p /dev/mtd3
	sync
	sleep 1
	[ -e /sys/class/ubi/ubi0 ] || exit 1
	mknod /dev/ubi0 c 250 0
	[ "$HAS_ENV" = "1" ] && ubimkvol /dev/ubi0 -n 0 -s 1MiB -N ubootenv && ubimkvol /dev/ubi0 -n 1 -s 1MiB -N ubootenv2
}

# Linksys E8450 got factory data in /dev/mtd2
# things may be shifted due to MTK BMT/BBT being used previously, fix that

install_prepare_backup

# make sure two mac addresses are store at correct offset in factory
install_fix_macpart /dev/mtd2 0x60000 0x1fff4

# make sure wifi eeprom starts at correct offset
magic="$(hexdump -v -n 2 -e '"%02x"' /dev/mtd2)"
[ "$magic" = "7622" ] || install_fix_factory /dev/mtd2

echo "redundantly write bl2 into the first 4 blocks"
for bl2start in 0x0 0x20000 0x40000 0x60000 ; do
	nandwrite -p -m -N -s $bl2start /dev/mtd0 $PRELOADER
done

echo "write FIP to NAND while skipping bad blocks"
nandwrite -p -m /dev/mtd1 $FIP

[ -e /sys/class/ubi/ubi0 ] || install_prepare_ubi

echo "write recovery ubi volume"
RECOVERY_SIZE=$(cat $RECOVERY | wc -c)
ubimkvol /dev/ubi0 -s $RECOVERY_SIZE -n 2 -N recovery
ubiupdatevol /dev/$(nand_find_volume ubi0 recovery) $RECOVERY

install_write_backup

sync

sleep 5

reboot -f
