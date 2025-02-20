#!/bin/sh

. /lib/functions.sh
. /lib/upgrade/nand.sh

led_pink() {
	echo 0 > /sys/class/leds/red:status/brightness
	echo 0 > /sys/class/leds/green:status/brightness
	echo 0 > /sys/class/leds/blue:status/brightness
	echo 80 > /sys/class/leds/green:status/brightness
	echo 32 > /sys/class/leds/red:status/brightness
	echo 48 > /sys/class/leds/blue:status/brightness
	echo timer > /sys/class/leds/green:status/trigger
	echo 1 > /sys/class/leds/green:status/delay_on
	echo 70 > /sys/class/leds/green:status/delay_off
}

led_red() {
	echo 0 > /sys/class/leds/red:status/brightness
	echo 0 > /sys/class/leds/green:status/brightness
	echo 0 > /sys/class/leds/blue:status/brightness
	echo 255 > /sys/class/leds/red:status/brightness
	echo timer > /sys/class/leds/red:status/trigger
	echo 120 > /sys/class/leds/red:status/delay_on
	echo 200 > /sys/class/leds/red:status/delay_off
}

led_green() {
	echo 0 > /sys/class/leds/red:status/brightness
	echo 0 > /sys/class/leds/green:status/brightness
	echo 0 > /sys/class/leds/blue:status/brightness
	echo 255 > /sys/class/leds/green:status/brightness
}

trigger_crash() {
	led_red
	sleep 5
	echo "INSTALLER: $@" > /dev/kmsg
	echo c > /proc/sysrq-trigger
}

led_pink

sleep 1

echo
echo OpenWrt UBI installer
echo

INSTALLER_DIR="/installer"
PRELOADER="$INSTALLER_DIR/mt7988-spim-nand-ubi-ddr4-bl2.img"
FIP="$INSTALLER_DIR/mt7988_asus_zenwifi-bt8-u-boot.fip"
RECOVERY="$(ls -1 $INSTALLER_DIR/openwrt-*mediatek-filogic-asus_zenwifi-bt8-initramfs-recovery.itb)"
HAS_ENV=1
HAS_FIP=1
HAS_FACTORY=1

if [ ! -s "$PRELOADER" ] || [ ! -s "$FIP" ] || [ ! -s "$RECOVERY" ]; then
	trigger_crash "Missing files. Aborting."
fi

ubi_mknod() {
	local dev="$1"
	dev="${dev##*/}"
	[ -e "/sys/class/ubi/$dev/uevent" ] || return 2
	source "/sys/class/ubi/$dev/uevent"
	mknod "/dev/$dev" c $MAJOR $MINOR
}

extract_ubi_volumes() {
	local mtdname="$1"
	local ubinum=31
	local mtdnum="$(find_mtd_index "$mtdname")"
	local voldev
	shift

	for volname in "$@"; do
		[ -e "/tmp/$volname" ] && return 1
	done

	ubiattach -m "$mtdnum" -d "$ubinum"
	ubi_mknod "/dev/ubi$ubinum"
	for volname in "$@"; do
		voldev="$(nand_find_volume "ubi$ubinum" "$volname")"
		[ "$voldev" ] || return 1
		dd if="/dev/$voldev" of="/tmp/$volname"
	done
	ubidetach -d "$ubinum"
	return 0
}

install_prepare_mtd_backup() {
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


led_pink() {
	echo 20 > /sys/class/leds/green:status/brightness
	echo 220 > /sys/class/leds/red:status/brightness
	echo 80 > /sys/class/leds/blue:status/brightness
}

# backup mtd0...mtd1, max. 16x 128kb block each (ie. 0x0~0x400000)
install_prepare_mtd_backup 1 16

extract_ubi_volumes OLD_UBI_DEV Factory Factory2 nvram || trigger_crash "Error extracting factory data"

cp /tmp/Factory /tmp/factory
mv /tmp/nvram /tmp/Factory* /tmp/backup

echo "redundantly write bl2"
for bl2start in 0x0 0x80000 0x100000 0x180000; do
	mtd -p $bl2start write $PRELOADER /dev/mtd0
done

install_prepare_ubi /dev/mtd$(find_mtd_index "newubi")

echo "write recovery ubi volume"
RECOVERY_SIZE=$(cat $RECOVERY | wc -c)
ubimkvol /dev/ubi0 -n 4 -s $RECOVERY_SIZE -N recovery
ubi_mknod ubi0_4
ubiupdatevol /dev/ubi0_4 $RECOVERY
ubimkvol /dev/ubi0 -n 5 -s 126976 -N fit

install_write_backup

sync

led_green

sleep 5

reboot -f
