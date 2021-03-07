# PoC OpenWrt UBI installer image genarator
for the Linksys E8450 aka. Belkin RT3200

![animated gif showing web UI and serial during installation](https://user-images.githubusercontent.com/9948313/108781223-78915500-7561-11eb-851a-3c4c744ad6c2.gif)
(serial is RX only for documentation, only interaction is HTTP file upload)

This script downloads the OpenWrt ImageBuilder to generate release-like (ie. including LuCI) sysupgrade image and then goes on and re-packages the initramfs image to once contain every needed for a recovery image permenently stored on the device and once to contain an installer script as well as images needed for the installation.
The resulting file `openwrt-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery-installer.itb` is suitable to be flashed by the vendor firmware Web-UI as well as non-UBI OpenWrt running on the device (use `sysupgrade -F openwrt-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery-installer.itb`).

**WARNING** This will replace the bootloader (TF-A 2.2, U-Boot 2020.10) and convert the flash layout of the device to UBI irreversibly!
If you ever want to go back to the vendor firmware, make sure you have made a complete backup of the flash BEFORE.

To use the script, you will need all OpenWrt build requirements installed as well as libfdt-dev which is needed by the installer-generater itself.

You may of course as well go ahead and download the generated files [here](https://github.com/dangowrt/linksys-e8450-openwrt-installer/releases/tag/v0.1).

## Steps

1. Upload `openwrt-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery-installer.itb` to vendor web interface upgrade page.
2. Wait for OpenWrt recovery image to come up.
3. Login and navigate to _System_ -> _Backup / Flash Firmware_ and then upload `openwrt-mediatek-mt7622-linksys_e8450-ubi-sysupgrade.itb` there.
4. Go ahead and setup OpenWrt
