# An OpenWrt UBI Installer Image Generator for Linksys E8450 and Belkin RT3200

![animated gif showing web UI and serial during installation](https://user-images.githubusercontent.com/9948313/108781223-78915500-7561-11eb-851a-3c4c744ad6c2.gif)

(The serial interface on the right is displaying RX only for documentation purposes, the interaction required for ordinary users can be done entirely within the web browser via HTTP file upload.)

This script downloads the OpenWrt ImageBuilder to generate a release-like (ie. LuCI included) sysupgrade image. The process involves re-packaging the initramfs image to contain everything necessary for a permanent recovery image within the NAND flash, including the installer script and the pre-requisite installation images.

The resulting file `openwrt-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery-installer.itb` can be flashed via the vendor/official firmware web interface, as well as OpenWrt firmware running non-UBI builds (by running `sysupgrade -F openwrt-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery-installer.itb`).

**WARNING** This will replace the bootloader (TF-A 2.4, U-Boot 2021.10) and convert the flash layout of the device to UBI! The installer stores a copy of the previous bootchain in a dedicated UBI volume `boot_backup`.

For utmost safety, you are recommended to make a complete backup of the device flash __**before**__ running the installer! (See below "Device Flash Backup Procedure")

You'll need the below to use the script to generate the installer image
* OpenWrt ImageBuilder
* `libfdt-dev`
* `cmake`

If you are not interested in building yourself, pre-built files are available [here](https://github.com/dangowrt/linksys-e8450-openwrt-installer/releases).

## Installing OpenWrt
#### (Assuming the device is running stock firmware, brand new or just after factory reset)

1. Connect any of the LAN ports of the device directly to the Ethernet port of your computer.
2. Set the IP address of your computer as `192.168.1.254` with netmask `255.255.255.0`, no gateway, no DNS.
3. Power on the device, wait about a minute for it to be ready.
4. Open a web browser, navigate to http://192.168.1.1 and wait for the wizard to come up.
5. Click *exactly* inside the radio button to confirm the terms and conditions, then abort the wizard.
6. You should then be greeted by the login screen, the stock password is "admin". (This step may be required for Linksys E8450 only)
7. Navigate to __Administration__ -> __Firmware Upgrade__
8. Upload `openwrt-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery-installer.itb`.
9. Wait for a few minutes, the OpenWrt recovery image should come up.
10. Login and navigate to __System__, save a copy of each of the `mtdblock`.
11. Upload `openwrt-mediatek-mt7622-linksys_e8450-ubi-squashfs-sysupgrade.itb`.
12. The device will reboot, you may proceed to setup OpenWrt.

## Upgrading to the Latest OpenWrt Snapshot Release.

**WARNING**

SNAPSHOT RELEASES ARE LARGELY UNTESTED!

PROCEED AT YOUR OWN RISK!

Attended Sysupgrade (auc) is included since version 0.6, all you need to do is to connect the router to the Internet and run `auc`.

## Post OpenWrt "recovery mode" Process

1. Hold down the "reset" button (below the "WPS" button) whilst powering on the device.
2. Release the button once the power LED turns into orange/yellow.

This will remove any user configuration and allow restoring or upgrading from [ssh](https://openwrt.org/docs/guide-user/installation/sysupgrade.cli)/http/[tftp](https://openwrt.org/docs/guide-user/installation/generic.flashing.tftp).

## Device Flash Backup Procedure

1. Flash `openwrt-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery.itb` (note that this file doesn't have the word _installer_ in it's filename)
2. Login and navigate to __System__, save a copy of each of the `mtdblock`.
3. In case of failure (because of ECC/OOB interoperability problems between the old and new SPI-NAND driver), connect to the device via SSH and enter the following commands:

```
cd /dev
for part in mtd[0123] ; do
  dd if=$part of=/tmp/$part
done
```

Then, copy the resulting files using scp to your host.

## Backup boot_backup ##

Connect to the device via SSH and enter the following commands:

```
mkdir /tmp/boot_backup
mount -t ubifs /dev/ubi0_3 /tmp/boot_backup
```

Then, copy the files under /tmp/boot_backup using scp to your host. These files can also be used in emergency case for reflashing via [JTAG](https://openwrt.org/toh/linksys/e8450#jtag)

## Restoring Vendor/Official Firmware ##

1. Flash `openwrt-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery.itb` (note that this file doesn't have the word _installer_ in it's filename)
2. Revert to the vendor mtd

```
mount -t ubifs /dev/ubi0_3 /mnt
cp /mnt/mtd* /tmp
ubidetach -d 0
mtd write /tmp/mtd0 /dev/mtd0
mtd write /tmp/mtd1 /dev/mtd1
mtd write /tmp/mtd2 /dev/mtd2
mtd write /tmp/mtd3 /dev/mtd3
```

3. Reboot the device, use TFTP to flash the vendor firmware according to [this](https://www.linksys.com/us/support-article?articleNum=137928)
