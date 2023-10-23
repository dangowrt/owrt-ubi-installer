## An OpenWrt UBI Installer Image Generator for Linksys E8450 and Belkin RT3200

https://user-images.githubusercontent.com/82453643/147394017-e7af122c-8234-4f11-8653-64d87ad8628d.mp4

_Showing the installation process. The window on the right displays the serial RX interface for documentation purpose only. The interaction required is shown on the left, which is done entirely within the web browser._

**WARNING #1** This will replace the bootloader (TF-A 2.4, U-Boot 2022.01) and convert the flash layout of the device to [UBI](https://github.com/dangowrt/owrt-ubi-installer/issues/9). The installer stores a copy of the previous bootchain in a dedicated UBI volume `boot_backup`.

**WARNING #2** Re-flashing the installer when the device is already using UBI flash layout will erase the previously backed up bootchain, which in most cases would be the vendor one.

**WARNING #3** If you plan to ever go back to the stock firmware, you will need a backup of the vendor bootchain. When going back to the stock firmware, be prepared to connect to the internal serial port in case there are any bad blocks.

**WARNING #4** The installer is meant to be executed only once per device. Executing the installer more than once should be avoided! Use normal `*-linksys_e8450-ubi-squashfs-sysupgrade.itb` images provided by openwrt.org instead.


## Table of Contents
- [Script information](#script-information)
- [Upgrading Stock Firmware](#upgrading-stock-firmware)
- [Installing OpenWrt](#installing-openwrt)
- [Backup vendor bootchain](#backup-vendor-bootchain)
- [Upgrading to the latest OpenWrt release](#upgrading-to-the-latest-openwrt-release)
- [Enter recovery mode under OpenWrt](#enter-recovery-mode-under-openwrt)
- [Restoring vendor firmware](#restoring-vendor-firmware)


## Script information
This script downloads the OpenWrt ImageBuilder to generate a firmware upgrade image compatible with the stock firmware which will automatically carry out the installation. The process involves re-packaging the _initramfs_ image to contain everything necessary for a permanent installation of a replacement Das U-Boot bootloader, ARM TrustedFirmware-A and an OpenWrt recovery (initramfs) image within the NAND flash, plus the installer script itself.

You'll need the below to use the script to generate the installer image:
- All [prerequisites of the OpenWrt ImageBuilder](https://openwrt.org/docs/guide-user/additional-software/imagebuilder#prerequisites)
- `libfdt-dev`
- `cmake`

**If you are not interested in building yourself**, the pre-built files are available [here](https://github.com/dangowrt/owrt-ubi-installer/releases).


## Upgrading Stock Firmware
- [ ] **IMPORTANT: Once you upgrade to "signed" firmware v1.2.x.x, you cannot roll back to previous "unsigned" firmware image, which is FW 1.1.x.x or 1.0.y.y.**

1. If your router is running FW version **1.1.00.180912 or below**, the router must first upgrade the firmware to **v1.1.01.272918 (Unsigned)** before you can upgrade the firmware to **v1.2.00.360516 (Signed) or above**. 
2. Download stock firmware and upgrade the router to the latest "**signed**" firmware:
   - [For Linksys E8450](https://www.linksys.com/support-article?articleNum=317332)
   - [For Belkin RT3200](https://www.belkin.com/support-article/?articleNum=208567)


## Installing OpenWrt
- [ ] **IMPORTANT: Execute these steps on a brand new device running stock firmware ...or... just after performing a factory reset on the device.**

1. Connect any of the LAN ports of the device directly to the Ethernet port of your computer.
2. Set the IP address of your computer as `192.168.1.254` with netmask `255.255.255.0`, no gateway, no DNS.
3. Power on the device, wait about a minute for it to be ready.
4. Open a web browser, navigate to http://192.168.1.1 and wait for the wizard to come up.
5. Complete the wizard.
6. You should then be greeted by the login screen.
7. Navigate to **Administration** -> **Firmware Upgrade**.
8. Upload the firmware "**installer_signed**" image:
   - `openwrt-...-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery-installer_signed.itb`
9. Wait for a minute, the OpenWrt recovery image should come up.
10. Navigate to **System** -> **Backup / Flash Firmware**.
11. Upload the firmware "**sysupgrade**" image:
    - `openwrt-...-mediatek-mt7622-linksys_e8450-ubi-squashfs-sysupgrade.itb`
12. The device will reboot, you may proceed to setup OpenWrt.
13. Follow the [post install tips in the OpenWrt Wiki](https://openwrt.org/toh/linksys/e8450#post_install_tips). You may proceed to setup OpenWrt.


## Backup vendor bootchain
Connect to the device via SSH and enter the following commands:
```
mkdir /tmp/boot_backup
mount -t ubifs ubi0:boot_backup /tmp/boot_backup
```

Then, copy the router files under `/tmp/boot_backup` using **scp** or [**WinSCP**](https://winscp.net/eng/downloads.php) to your computer. These files are needed in case you want to [restore the vendor firmware](#restoring-vendor-firmware). They can also be used in emergency case for reflashing via [JTAG](https://openwrt.org/toh/linksys/e8450#jtag).


## Upgrading to the latest OpenWrt release
- [ ] **IMPORTANT: Before upgrading you should [backup the vendor bootchain](#backup-vendor-bootchain), see above.**

1. Install a client for the sysupgrade service: either `luci-app-attendedsysupgrade` (Web UI) or `auc` (command line).
2. Navigate to **System** -> **Attended Sysupgrade**, or run `auc` from the command-line and proceed accordingly.
3. Or use **OpenWrt Firmware Selector** to build a custom "**sysupgrade**" image:
   - [**OpenWrt Firmware Selector**](https://firmware-selector.openwrt.org/?version=23.05.0&target=mediatek%2Fmt7622&id=linksys_e8450-ubi)


## Enter recovery mode under OpenWrt

#### Using the RESET button:
1. Hold down the "reset" button (below the "WPS" button) whilst powering on the device.
2. Release the button once the power LED turns into orange/yellow.

_This will remove any user configuration and allow restoring or upgrading from [ssh](https://openwrt.org/docs/guide-user/installation/sysupgrade.cli)/http/[tftp](https://openwrt.org/docs/guide-user/installation/generic.flashing.tftp)._

#### Using PSTORE/ramoops:
1. While running the production firmware enter this command in the shell:
   ```
   echo c > /proc/sysrq-trigger
   ```
2. Once the router has rebooted into recovery mode, clear PSTORE to make it reboot into production mode again:
   ```
   rm /sys/fs/pstore/*
   ```

_This keep user configuration but still allow restoring or upgrading from [ssh](https://openwrt.org/docs/guide-user/installation/sysupgrade.cli)/http/[tftp](https://openwrt.org/docs/guide-user/installation/generic.flashing.tftp)._


## Restoring vendor firmware
# :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning: :warning:
#### Bad blocks are **not** handled in the way the stock firmware and loader expects it. Ie. if you are lucky enough to own a device which got a bad block in the first ~22MiB of the SPI-NAND flash, then you will need to flash using TFTP which can only be triggered using the boot menu accessible via the serial console.
### Be prepared to open the device and wire up the serial console!

1. [Boot into recovery mode](#enter-recovery-mode-under-openwrt), either by flashing `openwrt-...-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery_signed.itb` (note that this file doesn't have the word "_installer_" in its filename) *or* by holding the RESET button while connecting the device to power *or* by using `echo c > /proc/sysrq-trigger` while running OpenWrt firmware.
2. Use **scp** or [**WinSCP**](https://winscp.net/eng/downloads.php) to copy the "_mtdx_" files to the `/tmp` folder on the router (the [backup of the vendor bootchain](#backup-vendor-bootchain) that you have on your computer and make sure that the size of the files is the same after copying them to the router).
3. [**Download the "signed" stock firmware**](#upgrading-stock-firmware), then rename the firmware to "**stock.img**" and use **scp** or [**WinSCP**](https://winscp.net/eng/downloads.php) to copy the "_stock.img_" file to the `/tmp` folder on the router (the same folder where you placed the _backup_ in **step 2**).
4. Connect to the device via SSH and enter the following commands:
   ```
   ubidetach -d 0
   insmod mtd-rw i_want_a_brick=1
   mtd write /tmp/mtd0 /dev/mtd0
   mtd write /tmp/mtd1 /dev/mtd1
   mtd write /tmp/mtd2 /dev/mtd2
   mtd write /tmp/mtd3 /dev/mtd3
   mtd -p 0x200000 write /tmp/stock.img /dev/mtd3
   ```
5. Reboot the device using the "reboot" comand and wait about a minute for it to be ready:
   ```
   reboot
   ```
6. Done.

**Note:** If your backup is from when only the "**unsigned**" stock firmware was available, you can follow above steps but flashing the **"unsigned" recovery image** `openwrt-...-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery.itb` (note that this file doesn't have the word "_installer_" or "_signed_" in its filename) and downloading the **"unsigned" stock firmware v1.0.01.101415** from below:
   * For Linksys E8450: [FW_E8450_1.0.01.101415_prod.img](https://downloads.linksys.com/support/assets/firmware/FW_E8450_1.0.01.101415_prod.img)
   * For Belkin RT3200: [FW_RT3200_1.0.01.101415_prod.img](https://s3.belkin.com/support/assets/belkin/firmware/FW_RT3200_1.0.01.101415_prod.img)
   * Do not use these "**unsigned**" stock firmwares if your device had a "**signed**" stock firmware version **>= 1.2.00.360516** before installing OpenWrt.
