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

[ -e /sys/class/ubi/ubi0 ] || {
	ubiformat -y /dev/mtd3
	ubiattach -p /dev/mtd3
	sync
	sleep 1
	[ -e /sys/class/ubi/ubi0 ] || exit 1
	mknod /dev/ubi0 c 250 0
	[ "$HAS_ENV" = "1" ] && ubimkvol /dev/ubi0 -n 0 -s 1MiB -N ubootenv && ubimkvol /dev/ubi0 -n 1 -s 1MiB -N ubootenv2
}

mtd -e /dev/mtd0 write $PRELOADER /dev/mtd0
mtd -e /dev/mtd1 write $FIP /dev/mtd1

RECOVERY_SIZE=$(cat $RECOVERY | wc -c)
ubimkvol /dev/ubi0 -s $RECOVERY_SIZE -n 2 -N recovery
ubiupdatevol /dev/$(nand_find_volume ubi0 recovery) $RECOVERY

sync

sleep 5

reboot -f
