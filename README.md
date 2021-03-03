# PoC OpenWrt UBI installer image genarator
for the Linksys E8450 aka. Belkin RT3200

![edit](https://user-images.githubusercontent.com/9948313/108781223-78915500-7561-11eb-851a-3c4c744ad6c2.gif)
(serial is RX only for documentation, only interaction is HTTP file upload)


This script downloads the OpenWrt ImageBuilder to generate release-like (ie. including LuCI) sysupgrade image and then goes on and re-packages the initramfs image to contain and installer script as well as images needed for the installation.
The resulting file is suitable to be flashed by the vendor firmware Web-UI as well as non-UBI OpenWrt running on the device.

**WARNING** This will replace the bootloader (TF-A 2.2, U-Boot 2020.10) and convert the flash layout of the device to UBI irreversibly!
If you ever want to go back to the vendor firmware, make sure you have made a complete backup of the flash BEFORE.

To use the script, you will need all OpenWrt build requirements installed as well as libfdt-dev which is needed by the installer-generater itself.
