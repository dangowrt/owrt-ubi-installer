# OpenWrt UBI installer image genarator
for the Linksys E8450 aka. Belkin RT3200

![animated gif showing web UI and serial during installation](https://user-images.githubusercontent.com/9948313/108781223-78915500-7561-11eb-851a-3c4c744ad6c2.gif)
(serial is RX only for documentation, only interaction is HTTP file upload)

This script downloads the OpenWrt ImageBuilder to generate release-like (ie. including LuCI) sysupgrade image and then goes on and re-packages the initramfs image to once contain everything needed for a recovery image permanently stored on the device and once to contain an installer script as well as images needed for the installation.
The resulting file `openwrt-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery-installer.itb` is suitable to be flashed by the vendor firmware Web-UI as well as non-UBI OpenWrt running on the device (use `sysupgrade -F openwrt-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery-installer.itb`).

**WARNING** This will replace the bootloader (TF-A 2.2, U-Boot 2020.10) and convert the flash layout of the device to UBI! The installer stores a copy of the previous bootchain in a dedicated UBI volume `boot_backup`. If you want to go back to the vendor firmware, you will have to boot into recovery mode (ie. initramfs),
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
6. At the login screen you are then being thrown at password 'admin' gets you back in.
7. Navigate to __Administration__ -> __Firmware Upgrade__
8. Upload `openwrt-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery-installer.itb` to vendor web interface upgrade page.
9. Wait for OpenWrt recovery image to come up.
10. Login and navigate to _System_ -> _Backup / Flash Firmware_ and then upload `openwrt-mediatek-mt7622-linksys_e8450-ubi-sysupgrade.itb` there.
11. Go ahead and setup OpenWrt
