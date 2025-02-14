## An OpenWrt UBI Installer Image Generator for Linksys E8450 and Belkin RT3200

https://user-images.githubusercontent.com/82453643/147394017-e7af122c-8234-4f11-8653-64d87ad8628d.mp4

*Showing the installation process. The window on the right displays the serial RX interface for documentation purpose only. The interaction required is shown on the left, which is done entirely within the web browser.*

**WARNING #1** This will replace the bootloader (TF-A 2.9, U-Boot 2024.01) and convert the flash layout of the device to [UBI](https://github.com/dangowrt/linksys-e8450-openwrt-installer/issues/9). The installer stores a copy of the previous bootchain in a dedicated UBI volume `boot_backup`.

**WARNING #2** Re-flashing the installer when the device is already using UBI flash layout will erase the previously backed up bootchain, which in most cases would be the vendor/official one.

If you plan to ever go back to the stock firmware, you will need a backup of the vendor bootchain and firmware. When going back to the stock firmware, be prepared to connect to the internal serial port in case there are any bad blocks.

**WARNING #3** The installer is meant to be executed only once per device unless an update explicitly requires a bootloader update. In that case, make sure to copy the content of the `boot_backup` UBI volume off the device before re-running the installer, so you will still have a copy of the stock bootchain! Executing the installer more than once should be avoided in all other cases! Use normal *-linksys_e8450-ubi-squashfs-sysupgrade.itb images provided by openwrt.org instead.

## Table of Contents
* [Script information](#script-information)
* [Installing OpenWrt](#installing-openwrt)
* [Upgrading to the latest OpenWrt snapshot](#upgrading-to-the-latest-openwrt-snapshot)
* [Enter recovery mode under OpenWrt](#enter-recovery-mode-under-openwrt)
* [Restoring the vendor/official firmware](#restoring-the-vendorofficial-firmware)


## Script information

This script downloads the OpenWrt ImageBuilder to generate a firmware upgrade image compatible with the stock firmware which will automatically carry out the installation. The process involves re-packaging the *initramfs* image to contain everything necessary for a permanent installation of a replacement Das U-Boot bootloader, ARM TrustedFirmware-A and an OpenWrt recovery (initramfs) image within the NAND flash, plus the installer script itself.

You'll need the below to use the script to generate the installer image:
* All [prerequisites of the OpenWrt ImageBuilder](https://openwrt.org/docs/guide-user/additional-software/imagebuilder#prerequisites) 
* `libfdt-dev`
* `cmake`
* `zstd`

**If you are not interested in building yourself**, the pre-built files are available [here](https://github.com/dangowrt/linksys-e8450-openwrt-installer/releases).

## Installing OpenWrt

* **IMPORTANT: *If* a device running stock 1.1.x firmware rejects the installer image, the recommended work-around is to downgrade the device to version 1.0.x, and then re-attempt uploading the installer image.  See "Downgrading Firmware" instructions below.**
* **IMPORTANT: Execute these steps on a brand new device running stock firmware ...or... just after performing a factory reset on the device.**

1. Connect any of the LAN ports of the device directly to the Ethernet port of your computer.
2. Set the IP address of your computer as `192.168.1.254` with netmask `255.255.255.0`, no gateway, no DNS.
3. Power on the device, wait about a minute for it to be ready.
4. Open a web browser, navigate to http://192.168.1.1 and wait for the wizard to come up.
5. Click *exactly* inside the radio button to confirm the terms and conditions, then abort the wizard. (Complete the wizard if you are running stock firmware version 1.2.x)
6. You should then be greeted by the login screen, the stock password is "admin".
7. Navigate to __Administration__ -> __Firmware Upgrade__.
8. Upload the firmware "installer" image
   * If running stock firmware < 1.2.00.273012, upload the **unsigned** image: `openwrt-...-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery-installer.itb`
   * Otherwise, when stock firmware is >= 1.2.00.273012, upload the **signed** image: `openwrt-...-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery-installer_signed.itb`
9. Wait for a minute, the OpenWrt recovery image should come up.
10. Navigate to __System__ -> __Backup / Flash Firmware__.
11. Upload `openwrt-...-mediatek-mt7622-linksys_e8450-ubi-squashfs-sysupgrade.itb`.
12. The device will reboot, you may proceed to setup OpenWrt.
13. Follow the [post install tips in the OpenWrt Wiki](https://openwrt.org/toh/linksys/e8450#post_install_tips). You may proceed to setup OpenWrt.

## Downgrading Stock Firmware - (If installer image upload was rejected)
* **IMPORTANT: Before downgrading, verify that the rejected upload was the correct, signed or unsigned, installer image to use for the currently running firmware version. (i.e. Maybe try uploading the 'other' installer image file first.)  Most rejected uploads are probably related to signed vs. unsigned image compatibility.**
* **Note: It may not be possible to downgrade devices with "signed" stock firmware, i.e. versions >= 1.2.00.273012.**
1. Download Stock Vendor Firmware
   * For Linksys E8450 [FW_E8450_1.0.01.101415_prod.img] (https://downloads.linksys.com/support/assets/firmware/FW_E8450_1.0.01.101415_prod.img)
   * For Belkin RT3200 [FW_RT3200_1.0.01.101415_prod.img] (https://s3.belkin.com/support/assets/belkin/firmware/FW_RT3200_1.0.01.101415_prod.img)
2. Upload / install the Vendor 1.0.x Firmware (using the normal procedure)

## Backup stock/vendor bootchain

Connect to the device via SSH and enter the following commands:

```
mkdir /tmp/boot_backup
mount -t ubifs ubi0:boot_backup /tmp/boot_backup
```

Then, copy the files under `/tmp/boot_backup` using *scp* to your computer. These files are needed in case you want to restore the original/vendor firmware. They can also be used in emergency case for reflashing via [JTAG](https://openwrt.org/toh/linksys/e8450#jtag).

## Upgrading to the latest OpenWrt release

0. Before upgrading you should backup the original/vendor bootchain, see above.

1. Install a client for the sysupgrade service: either `luci-app-attendedsysupgrade` (Web UI) or `auc` (command line).

2. Run `auc` from the command-line, or navigate to __System__ -> __Attended Sysupgrade__ and proceed accordingly.


## Enter recovery mode under OpenWrt


#### Using the RESET button:

1. Hold down the "reset" button (below the "WPS" button) whilst powering on the device.

2. Release the button once the power LED turns into orange/yellow.

This will remove any user configuration and allow restoring or upgrading from [ssh](https://openwrt.org/docs/guide-user/installation/sysupgrade.cli)/http/[tftp](https://openwrt.org/docs/guide-user/installation/generic.flashing.tftp).

#### Using PSTORE/ramoops

1. While running the production firmware enter this command in the shell

   ```
   echo c > /proc/sysrq-trigger
   ```

2. Once the router has rebooted into recovery mode, clear PSTORE to make it reboot into production mode again:

   ```
   rm /sys/fs/pstore/*
   ```

This keep user configuration but still allow restoring or upgrading from [ssh](https://openwrt.org/docs/guide-user/installation/sysupgrade.cli)/http/[tftp](https://openwrt.org/docs/guide-user/installation/generic.flashing.tftp).


## Restoring the vendor/official firmware ##
# :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: 
#### Bad blocks are **not** handled in the way the stock firmware and loader expects it. Ie. if you are lucky enough to own a device which got a bad block in the first ~22MiB of the SPI-NAND flash, then you will need to flash using TFTP which can only be triggered using the boot menu accessible via the serial console.
### Be prepared to open the device and wire up the serial console!

1. Boot into recovery mode, either by flashing `openwrt-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery.itb` (note that this file doesn't have the word _installer_ in its filename) *or* by holding the RESET button while connecting the device to power *or* by issuing `echo c > /proc/sysrq-trigger` while running the production firmware. 
2. Use **scp** or [WinSCP](https://winscp.net/eng/downloads.php) to copy the *mtdx* backup files to the `/tmp` folder on the router, which is the **original/vendor bootchain. Also upload the [**original/vendor firmware**](#downgrade-firmware).
3. Connect to the device via SSH and enter the following commands:
```
ubidetach -d 0
insmod mtd-rw i_want_a_brick=1
mtd write /tmp/mtd0 /dev/mtd0
mtd write /tmp/mtd1 /dev/mtd1
mtd write /tmp/mtd2 /dev/mtd2
mtd write /tmp/mtd3 /dev/mtd3
```
As the partition layout of the UBI-build also has changed, make sure to write things to the correct place in case your backup has been done at a point when the partition layout was different from what it is now.

Now write the **original/vendor firmware**:
```
# On Linksys E8450
mtd -p 0x200000 write /tmp/FW_E8450_1.0.01.101415_prod.img /dev/mtd3

# On Belkin RT3200
mtd -p 0x200000 write /tmp/FW_RT3200_1.0.01.101415_prod.img /dev/mtd3
```
4. Reboot the device and wait about a minute for it to be ready.
