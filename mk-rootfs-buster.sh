#!/bin/bash -e

# Directory contains the target rootfs
TARGET_ROOTFS_DIR="binary"

case "${ARCH:-$1}" in
	arm|arm32|armhf)
		ARCH=armhf
		;;
	*)
		ARCH=arm64
		;;
esac

echo -e "\033[36m Building for $ARCH \033[0m"

if [ ! $VERSION ]; then
	VERSION="release"
fi

if [ ! -e linaro-buster-alip-*.tar.gz ]; then
	echo -e "\033[36m Run mk-base-debian.sh first \033[0m"
	exit -1
fi

finish() {
	sudo umount $TARGET_ROOTFS_DIR/dev
	exit -1
}
trap finish ERR

echo -e "\033[36m Extract image \033[0m"
sudo tar -xpf linaro-buster-alip-*.tar.gz

# packages folder
sudo mkdir -p $TARGET_ROOTFS_DIR/packages
sudo cp -rf packages/$ARCH/* $TARGET_ROOTFS_DIR/packages

# overlay folder
sudo cp -rf overlay/* $TARGET_ROOTFS_DIR/

# overlay-firmware folder
sudo cp -rf overlay-firmware/* $TARGET_ROOTFS_DIR/

# overlay-debug folder
# adb, video, camera  test file
if [ "$VERSION" == "debug" ]; then
	sudo cp -rf overlay-debug/* $TARGET_ROOTFS_DIR/
fi
## hack the serial
sudo cp -f overlay/usr/lib/systemd/system/serial-getty@.service $TARGET_ROOTFS_DIR/lib/systemd/system/serial-getty@.service

# adb
if [[ "$ARCH" == "armhf" && "$VERSION" == "debug" ]]; then
	sudo cp -f overlay-debug/usr/local/share/adb/adbd-32 $TARGET_ROOTFS_DIR/usr/bin/adbd
elif [[ "$ARCH" == "arm64" && "$VERSION" == "debug" ]]; then
	sudo cp -f overlay-debug/usr/local/share/adb/adbd-64 $TARGET_ROOTFS_DIR/usr/bin/adbd
fi

# bt/wifi firmware
sudo mkdir -p $TARGET_ROOTFS_DIR/system/lib/modules/
sudo mkdir -p $TARGET_ROOTFS_DIR/vendor/etc
sudo find ../kernel/drivers/net/wireless/rockchip_wlan/*  -name "*.ko" | \
    xargs -n1 -i sudo cp {} $TARGET_ROOTFS_DIR/system/lib/modules/

echo -e "\033[36m Change root.....................\033[0m"
if [ "$ARCH" == "armhf" ]; then
	sudo cp /usr/bin/qemu-arm-static $TARGET_ROOTFS_DIR/usr/bin/
elif [ "$ARCH" == "arm64"  ]; then
	sudo cp /usr/bin/qemu-aarch64-static $TARGET_ROOTFS_DIR/usr/bin/
fi
sudo mount -o bind /dev $TARGET_ROOTFS_DIR/dev

cat << EOF | sudo chroot $TARGET_ROOTFS_DIR

apt-get update
apt-get upgrade -y

chmod o+x /usr/lib/dbus-1.0/dbus-daemon-launch-helper
chmod +x /etc/rc.local

#---------------system--------------
apt-get install -y git fakeroot devscripts cmake binfmt-support dh-make dh-exec pkg-kde-tools device-tree-compiler \
bc cpio parted dosfstools mtools dpkg-dev ntp rsyslog wget gdb net-tools inetutils-ping openssh-server \
ifupdown alsa-utils python vim ntp git vsftpd tcpdump can-utils i2c-tools strace network-manager onboard \
evtest sox libsox-fmt-all
apt-get install -f -y

#---------------power management --------------
apt-get install -y busybox pm-utils triggerhappy
cp /etc/Powermanager/triggerhappy.service  /lib/systemd/system/triggerhappy.service

#---------------Rga--------------
apt-get install -fy /packages/rga/*.deb

echo -e "\033[36m Setup Video.................... \033[0m"
apt-get install -y gstreamer1.0-plugins-bad gstreamer1.0-plugins-base gstreamer1.0-tools gstreamer1.0-alsa \
gstreamer1.0-plugins-base-apps qtmultimedia5-examples
apt-get install -f -y

apt-get install -fy /packages/mpp/*
apt-get install -fy /packages/gst-rkmpp/*.deb
apt-get install -fy /packages/gst-base/*.deb

#---------Camera---------
echo -e "\033[36m Install camera.................... \033[0m"
apt-get install cheese v4l-utils -y
apt-get install -fy /packages/rkisp/*.deb
apt-get install -fy /packages/libv4l/*.deb

#---------Xserver---------
echo -e "\033[36m Install Xserver.................... \033[0m"
apt-get install -fy /packages/xserver/*.deb

#---------------Openbox--------------
echo -e "\033[36m Install openbox.................... \033[0m"
apt-get install -fy /packages/openbox/*.deb

#---------update chromium-----
apt-get install -fy /packages/chromium/*.deb

#------------------libdrm------------
echo -e "\033[36m Install libdrm.................... \033[0m"
apt-get install -fy /packages/libdrm/*.deb

#------------------libdrm-cursor------------
echo -e "\033[36m Install libdrm-cursor.................... \033[0m"
apt-get install -fy /packages/libdrm-cursor/*.deb

# Only preload libdrm-cursor for X
sed -i "/libdrm-cursor.so/d" /etc/ld.so.preload
sed -i "1aexport LD_PRELOAD=libdrm-cursor.so.1" /usr/bin/X

#------------------pcmanfm------------
echo -e "\033[36m Install pcmanfm.................... \033[0m"
apt-get install -fy /packages/pcmanfm/*.deb

#------------------rkwifibt------------
echo -e "\033[36m Install rkwifibt.................... \033[0m"
apt-get install -fy /packages/rkwifibt/*.deb
ln -s /system/etc/firmware /vendor/etc/

if [ "$VERSION" == "debug" ]; then
#------------------glmark2------------
echo -e "\033[36m Install glmark2.................... \033[0m"
apt-get install -fy /packages/glmark2/*.deb
fi

# mark package to hold
apt list --installed | grep -w local | cut -d/ -f1 | xargs apt-mark hold

#---------------Custom Script--------------
systemctl mask systemd-networkd-wait-online.service
systemctl mask NetworkManager-wait-online.service
rm /lib/systemd/system/wpa_supplicant@.service

#---------------Clean--------------
rm -rf /var/lib/apt/lists/*

EOF

sudo umount $TARGET_ROOTFS_DIR/dev
