## An OpenWrt UBI Installer Image Generator for Linksys E8450 and Belkin RT3200

https://user-images.githubusercontent.com/82453643/147394017-e7af122c-8234-4f11-8653-64d87ad8628d.mp4

*Showing the installation process. The window on the right displays the serial RX interface for documentation purpose only. The interaction required is shown on the left, which is done entirely within the web browser.*

**WARNING #1** This will replace the bootloader (TF-A 2.4, U-Boot 2021.10) and convert the flash layout of the device to [UBI](https://github.com/dangowrt/linksys-e8450-openwrt-installer/issues/9). The installer stores a copy of the previous bootchain in a dedicated UBI volume `boot_backup`.

**WARNING #2** Re-flashing the installer when the device is already using UBI flash layout will erase the previously backed up bootchain, which in most cases would be the vendor/official one.

It's recommended that you make a **complete backup** of the device flash __**before**__ running the installer. (see below "[Device flash complete backup procedure](#device-flash-complete-backup-procedure)")

## Table of Contents
* [Script information](#script-information)
* [Downgrade firmware](#downgrade-firmware)
* [Device flash complete backup procedure](#device-flash-complete-backup-procedure)
* [Installing OpenWrt](#installing-openwrt)
* [Upgrading to the latest OpenWrt snapshot](#upgrading-to-the-latest-openwrt-snapshot)
* [Enter recovery mode under OpenWrt](#enter-recovery-mode-under-openwrt)
* [Restoring the vendor/official firmware](#restoring-the-vendorofficial-firmware)


## Script information

This script downloads the OpenWrt ImageBuilder to generate a release-like (i.e. LuCI included) *sysupgrade* image. The process involves re-packaging the *initramfs* image to contain everything necessary for a permanent recovery image within the NAND flash, including the installer script and the prerequisite installation images.

You'll need the below to use the script to generate the installer image:
* All [prerequisites of the OpenWrt ImageBuilder](https://openwrt.org/docs/guide-user/additional-software/imagebuilder#prerequisites) 
* `libfdt-dev`
* `cmake`

**If you are not interested in building yourself**, the pre-built files are available [here](https://github.com/dangowrt/linksys-e8450-openwrt-installer/releases).

## Downgrade firmware

#### Upstream firmware version 1.1 and newer rejects the installer image. As a temporary workaround, please downgrade to version 1.0 before running the installer.

 * For Linksys E8450 [FW_E8450_1.0.01.101415_prod.img](https://downloads.linksys.com/support/assets/firmware/FW_E8450_1.0.01.101415_prod.img)
 * For Belkin RT3200 [FW_RT3200_1.0.01.101415_prod.img](https://www.belkin.com/support/assets/belkin/firmware/FW_RT3200_1.0.01.101415_prod.img)

## Device flash complete backup procedure

#### Assuming the device is running stock firmware version 1.0

1. Flash `openwrt-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery.itb` (note that this file doesn't have the word _installer_ in its filename)
2. Login [http://192.168.1.1](http://192.168.1.1/cgi-bin/luci/admin/system/flash), then navigate to **System -> Backup / Flash Firmware** and save a copy of each of the `mtdblock`.
3. Now we are going to make a **complete backup** of the device (**includes original/vendor firmware**), connect to the device via SSH and enter the following commands:

```
cd /dev
for part in mtd[0123] ; do
  dd if=$part of=/tmp/$part
done
```

4. Then, copy the resulting **mtdx** files found in the `/tmp` folder on the router to the computer using **scp** or [WinSCP](https://winscp.net/eng/downloads.php) (the size of the *mtd3* file has to be **125MB** and make sure the size of the other files is the same, when you copy them to the computer).
5. **Perform a powercycle** to reboot into the original/vendor firmware (**to perform a powercycle**, unplug the device from the power source for about 30 seconds before plugging it back).
6. When the device is running **original/vendor firmware**, perform a factory reset.

Do not attempt to flash `openwrt-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery-installer.itb` from the running **initramfs system** -- it will fail to reboot, possibly requiring serial console access. Instead, **powercycle** the device to reboot into the original non-ubi firmware, and then flash the `installer` version.

## Installing OpenWrt

#### Assuming the device is running stock firmware version 1.0, and is brand new or just after factory reset.

1. Connect any of the LAN ports of the device directly to the Ethernet port of your computer.
2. Set the IP address of your computer as `192.168.1.254` with netmask `255.255.255.0`, no gateway, no DNS.
3. Power on the device, wait about a minute for it to be ready.
4. Open a web browser, navigate to http://192.168.1.1 and wait for the wizard to come up.
5. Click *exactly* inside the radio button to confirm the terms and conditions, then abort the wizard.
6. You should then be greeted by the login screen, the stock password is "admin".
7. Navigate to __Administration__ -> __Firmware Upgrade__.
8. Upload `openwrt-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery-installer.itb`.
9. Wait for a minute, the OpenWrt recovery image should come up.
9. Navigate to __System__ -> __Backup / Flash Firmware__.
10. Upload `openwrt-mediatek-mt7622-linksys_e8450-ubi-squashfs-sysupgrade.itb`.
12. The device will reboot, you may proceed to setup OpenWrt.

## Upgrading to the latest OpenWrt snapshot 

**WARNING**
SNAPSHOTS ARE LARGELY UNTESTED!
PROCEED AT YOUR OWN RISK!

1. Backup the original/vendor bootchain (**does not include original/vendor firmware**).

   Connect to the device via SSH and enter the following commands:

   ```
   mkdir /tmp/boot_backup
   mount -t ubifs ubi0:boot_backup /tmp/boot_backup
   ```

   Then, copy the files under `/tmp/boot_backup` using *scp* to your computer. These files are needed in case you want to restore the original/vendor firmware. They can also be used in emergency case for reflashing via [JTAG](https://openwrt.org/toh/linksys/e8450#jtag).

2. Both `auc` (attended sysupgrade command-line client) and `luci-app-attendedsysupgrade` (LuCI web-interface counterpart) are included since version 0.6. Simply run `auc` from the command-line, or navigate to __System__ -> __Attended Sysupgrade__ and proceed accordingly.

## Enter recovery mode under OpenWrt

1. Hold down the "reset" button (below the "WPS" button) whilst powering on the device.
2. Release the button once the power LED turns into orange/yellow.

This will remove any user configuration and allow restoring or upgrading from [ssh](https://openwrt.org/docs/guide-user/installation/sysupgrade.cli)/http/[tftp](https://openwrt.org/docs/guide-user/installation/generic.flashing.tftp).


## Restoring the vendor/official firmware ##

1. Boot into recovery mode, either by flashing `openwrt-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery.itb` (note that this file doesn't have the word _installer_ in its filename) *or* by holding the RESET button while connecting the device to power *or* by issuing `echo c > /proc/sysrq-trigger` while running the production firmware. 
2. Use **scp** or [WinSCP](https://winscp.net/eng/downloads.php) to copy the *mtdx* files to the `/tmp` folder on the router (the [**complete backup**](#device-flash-complete-backup-procedure) that you have on your computer), which is the **original/vendor bootchain and firmware** (the size of the *mtd3* file has to be **125MB** and make sure the size of the other files is the same, when you copy them to the router). In case you only got the [**minimal backup**](#upgrading-to-the-latest-openwrt-snapshot) (*mtd3* file size is **2MB**), also upload the [**original/vendor firmware**](#downgrade-firmware).
3. Connect to the device via SSH and enter the following commands:
```
ubidetach -d 0
insmod mtd-rw i_want_a_brick=1
mtd write /tmp/mtd0 /dev/mtd0
mtd write /tmp/mtd1 /dev/mtd1
mtd write /tmp/mtd2 /dev/mtd2
mtd write /tmp/mtd3 /dev/mtd3
```
In case you were using the [**minimal backup**](#upgrading-to-the-latest-openwrt-snapshot) files, now write the **original/vendor firmware**:
```
# On Linksys E8450
mtd -p 0x200000 write /tmp/FW_E8450_1.0.01.101415_prod.img /dev/mtd3

# On Belkin RT3200
mtd -p 0x200000 write /tmp/FW_RT3200_1.0.01.101415_prod.img /dev/mtd3
```
4. Reboot the device and wait about a minute for it to be ready.
5. If you use the [**complete backup**](#device-flash-complete-backup-procedure), after rebooting, the router will boot into the **initramfs system**, you will need **perform a powercycle** to reboot into the original/vendor firmware (**to perform a powercycle**, unplug the device from the power source for about 30 seconds before plugging it back).

**Note:** Be prepared to connect the serial console as bad blocks are **not** handled in the way the stock firmware and loader expects it. Ie. if you are lucky enough to own a device which got a bad block in the first ~22MiB of the SPI-NAND flash, then you will need to flash using TFTP which can only be triggered using the boot menu accessible via the serial console.
