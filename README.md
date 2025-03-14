## An OpenWrt UBI Installer Image Generator for ASUS ZenWiFi BT8

**WARNING #1** This will replace the bootloader (TF-A 2.12, U-Boot 2025.01) and convert the flash layout of the device to an all-in-UBI layout. The installer stores a copy of the previous bootchain in a dedicated UBI volume `boot_backup`.

**WARNING #2** Re-flashing the installer when the device is already using UBI flash layout will erase the previously backed up bootchain, which in most cases would be the vendor/official one.

If you plan to ever go back to the stock firmware, you will need a backup of the vendor bootchain and firmware.

**WARNING #3** The installer is meant to be executed only once per device.

## Table of Contents
* [Script information](#script-information)
* [Installing OpenWrt](#installing-openwrt)
* [Enter recovery mode under OpenWrt](#enter-recovery-mode-under-openwrt)


## Script information

This script downloads the OpenWrt ImageBuilder to generate a firmware upgrade image compatible with the stock firmware which will automatically carry out the installation. The process involves re-packaging the *initramfs* image to contain everything necessary for a permanent installation of a replacement Das U-Boot bootloader, ARM TrustedFirmware-A and an OpenWrt recovery (initramfs) image within the NAND flash, plus the installer script itself.

You'll need the below to use the script to generate the installer image:
* All [prerequisites of the OpenWrt ImageBuilder](https://openwrt.org/docs/guide-user/additional-software/imagebuilder#prerequisites) 
* `libfdt-dev`
* `cmake`
* `zstd`

**If you are not interested in building yourself**, the pre-built files are available [here](https://github.com/dangowrt/linksys-e8450-openwrt-installer/releases).

## Installing OpenWrt

1. Hold down RESET button and power on the device until
   LED pulses red.

2. Assign IP 192.168.1.70/24 to your computer's Ethernet port

3. Connect Ethernet to one of the 1GE LAN ports

4. Open browser and visit http://192.168.1.1/

5. Upload `openwrt-mediatek-filogic-asus_zenwifi-bt8-ubootmod-initramfs-recovery-installer.trx`

6. Once OpenWrt initramfs system comes up, do sysupgrade using
   `openwrt-mediatek-filogic-asus_zenwifi-bt8-ubootmod-squashfs-sysupgrade.bin`

## Backup stock/vendor bootchain

Connect to the device via SSH and enter the following commands:

```
mkdir /tmp/boot_backup
mount -t ubifs ubi0:boot_backup /tmp/boot_backup
```

Then, copy the files under `/tmp/boot_backup` using *scp* to your computer. These files are needed in case you want to restore the original/vendor firmware. They can also be used in emergency case for reflashing via [JTAG](https://openwrt.org/toh/linksys/e8450#jtag).


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
