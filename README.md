# An OpenWrt UBI installer image generator
Supporting the: "Linksys E8450", and the "Belkin RT3200".(aka "Belkin AX3200")

![animated gif showing web UI and serial during installation](https://user-images.githubusercontent.com/9948313/108781223-78915500-7561-11eb-851a-3c4c744ad6c2.gif)
(The serial interface is displaying RX only for documentation purposes as the only interaction required is from within the web browser via HTTP file upload.)

This script downloads the OpenWrt ImageBuilder to generate a release-like (ie. including LuCI) sysupgrade image. 
The process involves re-packaging the initramfs image to contain everything necessary for a permanent recovery image within NAND flash including the installer script and the prerequisite installation images.

The resulting file `openwrt-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery-installer.itb` is suitable to be flashed by the vendor firmware Web-UI as well as non-UBI OpenWrt running on the device (use `sysupgrade -F openwrt-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery-installer.itb`).

**WARNING** This will replace the bootloader (TF-A 2.4, U-Boot 2021.10) and convert the flash layout of the device to UBI! The installer stores a copy of the previous bootchain in a dedicated UBI volume `boot_backup`. If you want to go back to the vendor firmware, you will have to boot into recovery mode (ie. initramfs),
copy those files into `/tmp`, umount the UBI volume, detach the UBI device and then write the files to the corresponding MTD partitions (mtd write $file /dev/mtdX).

To be on the safe side, it is still recommended to make a complete backup of the device flash __**before**__ running the installer!

To use the script to generate the installer image, you will need all runtime requirements of the OpenWrt ImageBuilder installed as well as `libfdt-dev` and `cmake` which is needed by the installer-generator itself.

You may of course as well go ahead and download the generated files [here](https://github.com/dangowrt/linksys-e8450-openwrt-installer/releases).

## Steps
#### (assuming the device runs stock firmware and is new or just after factory reset)

1. Connect any of the LAN ports of the device directly to the Ethernet port of your PC.
2. Configure the IP address of the PC to be `192.168.1.254`, netmask `255.255.255.0`, no gateway, no DNS.
3. Power on the device, wait about a minute for it to be ready.
4. Open a web browser and navigate to http://192.168.1.1 and wait for the wizard to come up.
5. Click *exactly* inside the radio button to confirm you have read the terms and conditions, then abort the wizard.
6. You should then be greeted by the login screen, the stock password is "admin". (This step might only apply to the Linksys, everything else remains the same) 
7. Navigate to __Administration__ -> __Firmware Upgrade__
8. Upload `openwrt-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery-installer.itb` to vendor web interface upgrade page.
9. Wait for OpenWrt recovery image to come up.
10. Login and navigate to __System__ -> __Backup / Flash Firmware__
11. Upload the `openwrt-mediatek-mt7622-linksys_e8450-ubi-sysupgrade.itb` file.
12. Reboot and proceed to a normal OpenWrt setup (or upload your configuration file).

## Upgrading to OpenWrt snapshot release.

**WARNING**

SNAPSHOT RELEASES ARE LARGELY UNTESTED!

PROCEED AT YOUR OWN RISK!

1. If you haven't already, backup every "mtdblock" category, and move the "boot_backup" to another device. (In the event of emergency you can reflash via [JTAG](https://openwrt.org/toh/linksys/e8450#jtag)
2. `ssh root@192.168.1.1 -p 22`
3. Connect the WAN port to a router with internet, and DHCP
4. Install `auc` package as follows:
```
opkg update
opkg install auc
```
(instead of using `auc` on the console you may as well use `luci-app-attendedsysupgrade` for a Web-UI version of the updater)

5. Run `auc` (or open attended sysupgrade tab in LuCI)
6. Once completed, the system will reboot with current snapshot firmware.

(Verified with the April 6th 2021 Snapshot release)

## Post OpenWrt "recovery mode" process
1. Hold down the "reset" button below the "WPS" button whilst powering on the device.
2. Release the button once the power LED turns a orange/yellow color.

This will remove any user configuration errors and allow restoring or upgrading from [ssh](https://openwrt.org/docs/guide-user/installation/sysupgrade.cli)/http/[tftp](https://openwrt.org/docs/guide-user/installation/generic.flashing.tftp).
