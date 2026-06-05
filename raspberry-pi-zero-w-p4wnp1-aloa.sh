#!/usr/bin/env bash
#
# Kali Linux ARM build-script for Raspberry Pi Zero W (P4wnP1 A.L.O.A.) (32-bit)
# Source: https://gitlab.com/kalilinux/build-scripts/kali-arm
#
# This is a community script - you will need to generate your own image to use
# More information: https://www.kali.org/docs/arm/raspberry-pi-zero-w-p4wnp1-aloa/
#
# Due to the nexmon firmware's age, there is a lack of recognizing arm64.
# This script cannot be run on an arm64 host.
set -e

# Hardware model
hw_model=${hw_model:-"raspberry-pi-zero-w-p4wnp1-aloa"}

# Custom hostname
hostname="p4wnp1"

# Architecture
architecture=${architecture:-"armhf"}

# Desktop manager (xfce, gnome, i3, kde, lxde, mate, e17 or none)
desktop=${desktop:-"none"}

host_arch="$(uname -m)"
if [[ "${host_arch}" == "aarch64" || "${host_arch}" == "arm64" ]]; then
    echo "Error: ${hw_model} build is not supported on arm64 hosts (${host_arch}). Use an x86_64 host." >&2
    exit 1
fi

if ! command -v arm-linux-gnueabihf-gcc >/dev/null 2>&1; then
    echo "Error: missing arm-linux-gnueabihf-gcc. Run ./common.d/build_deps.sh first." >&2
    exit 1
fi

if [ ! -x /usr/bin/qemu-arm-static ]; then
    echo "Error: missing /usr/bin/qemu-arm-static. Run ./common.d/build_deps.sh first." >&2
    exit 1
fi

# Load default base_image configs
source ./common.d/base_image.sh

host_mem_kib="$(awk '/MemTotal:/ {print $2}' /proc/meminfo)"
host_swap_kib="$(awk '/SwapTotal:/ {print $2}' /proc/meminfo)"
avail_disk_kib="$(df --output=avail -k "${repo_dir}" | awk 'NR==2 {print $1}')"

if [ "${avail_disk_kib}" -lt 30000000 ]; then
    echo "Error: insufficient free disk space (<30 GiB). Free space and retry." >&2
    exit 1
fi

kernel_jobs="${kernel_jobs:-$(nproc)}"
if [ "${host_mem_kib}" -lt 8000000 ]; then
    echo "Warning: host RAM is below 8 GiB; reducing kernel build parallelism to avoid OOM." >&2
    kernel_jobs=1
fi

if [ "${host_swap_kib}" -lt 4000000 ]; then
    echo "Warning: host swap is below 4 GiB; kernel build stability may be reduced." >&2
fi

# Network configs
basic_network
#add_interface eth0

# move P4wnP1 in (change to release blob when ready)
git clone -b 'master' --single-branch --depth 1 https://github.com/rogandawes/P4wnP1_aloa "${work_dir}"/root/P4wnP1

# Third stage
cat <<EOF >>"${work_dir}"/third-stage
status_stage3 'Copy rpi services'
cp -p /bsp/services/rpi/*.service /etc/systemd/system/

status_stage3 'Script mode wlan monitor START/STOP'
install -m755 /bsp/scripts/monstart /usr/bin/
install -m755 /bsp/scripts/monstop /usr/bin/

# haveged: assure enough entropy data for hostapd on startup
# avahi-daemon: allow mDNS resolution (apple bonjour) by remote hosts
# dhcpcd5: REQUIRED (P4wnP1 A.L.O.A. currently wraps this binary if a DHCP client is needed)
# dnsmasq: REQUIRED (P4wnP1 A.L.O.A. currently wraps this binary if a DHCP server is needed, currently not used for DNS)
# dosfstools: contains fatlabel (used to label FAT32 iamges for UMS)
# genisoimage: allow creation of CD-Rom iso images for CD-Rom USB gadget from existing folders on the fly
# iodine: allow DNS tunneling
status_stage3 'Install needed packages for P4wnp1 A.L.O.A'
# Include serial tools (minicom, socat, python3-serial) so UART send/receive works programmatically and interactively
# NOTE: The full "kali-tools-wireless" metapackage is intentionally NOT used here:
#   * it pulls in hostapd-wpe, whose postinst generates a TLS cert with OpenSSL that
#     fails under qemu-user emulation (errno 38/ENOSYS), breaking the cross-build, and
#   * it drags in LLVM/Mesa/Vulkan/GTK/gnuradio/SDR/VNC (hundreds of MB) that do not
#     belong on a headless 512 MB RPi Zero W.
# The wireless tools P4wnP1 actually needs are installed directly below
# (hostapd for AP mode, wpasupplicant for client mode, aircrack-ng for auditing).
eatmydata apt-get install -y apache2 atftpd autossh avahi-daemon bash-completion bluez bluez-firmware build-essential dhcpcd5 dnsmasq dosfstools fake-hwclock firmware-atheros genisoimage golang haveged hostapd i2c-tools iodine aircrack-ng openssh-server openvpn pi-bluetooth polkitd pkexec python3-configobj python3-dev python3-pip python3-requests python3-smbus python3-serial minicom socat wpasupplicant

status_stage3 'Remove NetworkManager'
eatmydata apt-get purge -y network-manager

status_stage3 'Enabling ssh by putting ssh or ssh.txt file in /boot/firmware'
systemctl enable enable-ssh

status_stage3 'Fixup wireless-regdb signature'
update-alternatives --set regulatory.db /lib/firmware/regulatory.db-upstream

status_stage3 'Disable Bluetooth and free PL011 UART'
systemctl disable hciuart
systemctl disable bluetooth

status_stage3 'Set root password'
echo "root:toor" | chpasswd

status_stage3 'Remove persistent net rules file'
rm -f /etc/udev/rules.d/70-persistent-net.rules

status_stage3 'Allow root to ssh in'
sed -i -e 's/^#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

status_stage3 'Disable dhcpcd'
# dhcpcd is needed by P4wnP1, but started on demand
# installation of dhcpcd5 package enables a systemd unit starting dhcpcd for all
# interfaces, which results in conflicts with DHCP servers running on created
# bridge interface (especially for the bteth BNEP bridge). To avoid this we
# disable the service. If communication problems occur, although DHCP leases
# are handed out by dnsmasq, dhcpcd should be the first place to look
# (no interface should hava an APIPA addr assigned, unless the DHCP client
# was explcitely enabled by P4wnP1 for this interface)
systemctl disable dhcpcd

status_stage3 'Enable serial getty on UART (ttyAMA0)'
systemctl enable serial-getty@ttyAMA0.service

status_stage3 'Run P4wnP1 A.L.O.A installer'
cd /root/P4wnP1
# This is one case where we actually want the pip install to be system wide.
sed -i -e 's/sudo pip install pydispatcher/pip install --break-system-packages pydispatcher/' Makefile
status_stage3 'Set custom default WiFi SSID/PSK'
# Update the fallback script with user provided credentials
sed -i 's/-s "💥🖥💥 Ⓟ➃ⓌⓃ🅟❶"/-s "xxxXxxx"/' dist/scripts/servicestart.sh
sed -i 's/-k "MaMe82-P4wnP1"/-k "Birds254$"/' dist/scripts/servicestart.sh
make installkali

status_stage3 'Enable dwc2 module'
grep -qxF 'dwc2' /etc/modules || echo "dwc2" >> /etc/modules

status_stage3 'Enable root login over ttyGS0'
grep -qxF 'ttyGS0' /etc/securetty || echo "ttyGS0" >> /etc/securetty

status_stage3 'Add cronjob to update fake-hwclock'
echo '* * * * * root /usr/sbin/fake-hwclock' >> /etc/crontab

status_stage3 'Create rc.local to remove kernel output on the console'
echo "#!/bin/sh -e" > /etc/rc.local
echo "dmesg -D" >> /etc/rc.local
echo "exit 0" >> /etc/rc.local
chmod +x /etc/rc.local

# Despite the name, all this does is disable root login over ssh
# which we want to enable on this image.
status_stage3 'Remove ssh key check'
rm /etc/runonce.d/03-check-ssh-keys

# Copy in bluetooth overrides
status_stage3 'Add systemd service overrides for bluetooth'
cp -a /bsp/overrides/* /etc/systemd/system/

# Create spi and gpio groups
status_stage3 'Add spi and gpio groups'
groupadd -f -r spi
groupadd -f -r gpio

# We don't care about console font on this image.
status_stage3 'Disable console-setup service'
systemctl disable console-setup

status_stage3 'Purge common GUI packages to ensure headless image'
# Purge common X/desktop packages if present (non-fatal if packages are absent)
eatmydata apt-get purge -y --allow-change-held-packages xserver-xorg lightdm gdm3 sddm xfce4 lxde-core lxde lxsession || true
# Mask display managers and disable graphical.target
systemctl mask lightdm.service gdm3.service sddm.service || true
systemctl set-default multi-user.target || true
EOF

# Run third stage
include third_stage

cd "${base_dir}"

status 'Clone bootloader and firmware'
git clone -b 1.20181112 --depth 1 https://github.com/raspberrypi/firmware.git "${work_dir}"/rpi-firmware
mkdir -p "${work_dir}"/boot/firmware
cp -rf "${work_dir}"/rpi-firmware/boot/* "${work_dir}"/boot/firmware/

# Copy over Pi specific libs (video core) and binaries (dtoverlay,dtparam...)
cp -rf "${work_dir}"/rpi-firmware/opt/* "${work_dir}"/opt/
rm -rf "${work_dir}"/rpi-firmware

status 'Clone nexmon firmware'
cd "${base_dir}"
git clone https://github.com/mame82/nexmon_wifi_covert_channel.git -b p4wnp1 "${base_dir}"/nexmon --depth 1

status 'Clone and build kernel'
cd "${base_dir}"

# Re4son kernel 4.14.80 with P4wnP1 patches (dwc2 and brcmfmac)
git clone --depth 1 https://github.com/Re4son/re4son-raspberrypi-linux -b rpi-4.14.80-re4son-p4wnp1 "${work_dir}"/usr/src/kernel

cd "${work_dir}"/usr/src/kernel

# Remove redundant yyloc global declaration
patch -p1 --no-backup-if-mismatch <"${repo_dir}"/patches/11647f99b4de6bc460e106e876f72fc7af3e54a6.patch

# Fix ARMv6 architecture selection for modern (gcc-11+) cross toolchains.
# The kernel's arch/arm/Makefile probes "-march=armv6" with $(cc-option) BEFORE
# -msoft-float is applied. gcc-11+ then errors with "selected architecture lacks
# an FPU" for the hard-float toolchain, so the probe silently falls back to
# -march=armv5t and the assembler rejects ARMv6 instructions (cpsid/ldrex/strex).
# Hardcoding -march=armv6/armv6k removes the broken probe; the real compile still
# appends -msoft-float, so the FPU objection no longer applies. See Debian #996419.
sed -i -E 's#^arch-\$\(CONFIG_CPU_32v6\)[[:space:]].*#arch-$(CONFIG_CPU_32v6) =-D__LINUX_ARM_ARCH__=6 -march=armv6#' arch/arm/Makefile
sed -i -E 's#^arch-\$\(CONFIG_CPU_32v6K\)[[:space:]].*#arch-$(CONFIG_CPU_32v6K) =-D__LINUX_ARM_ARCH__=6 -march=armv6k#' arch/arm/Makefile
grep -nE '^arch-\$\(CONFIG_CPU_32v6K?\)' arch/arm/Makefile || true

# Note: Compiling the kernel in /usr/src/kernel of the target file system is problematic, as the binaries of the compiling host architecture
# get deployed to the /usr/src/kernel/scripts subfolder (in this case linux-x64 binaries), which is symlinked to /usr/src/build later on
# This would f.e. hinder rebuilding single modules, like nexmon's brcmfmac driver, on the Pi itself (online compilation)
# The cause:building of modules relies on the pre-built binaries in /usr/src/build folder. But the helper binaries are compiled with the
# HOST toolchain and not with the crosscompiler toolchain (f.e. /usr/src/kernel/script/basic/fixdep would end up as x64 binary, as this helper
# is not compiled with the CROSS toolchain). As those scripts are used druing module build, it wouldn't work to build on the pi, later on,
# without recompiling the helper binaries with the proper crosscompiler toolchain
#
# To account for that, the 'script' subfolder could be rebuild on the target (online) by running `make scripts/` from /usr/src/kernel folder
# Rebuilding the script, again, depends on additional tooling, like `bc` binary, which has to be installed
#
# Currently the step of recompiling the kernel/scripts folder has to be done manually online, but it should be possible to do it after kernel
# build, by setting the host compiler (CC) to the gcc of the linaro-arm-linux-gnueabihf-raspbian-x64 toolchain (not only the CROSS_COMPILE)
# The problem is, that the used linaro toolchain builds for armhf (not a problem for kernel, as there're no dependencies on hf librearies),
# but the debian packages (and the provided gcc) are armel
#
# To clean up this whole "armel" vs "armhf" mess, the kernel should be compiled with a armel toolchain (best choice would be the toolchain
# which is used to build the kali armel packages itself, which is hopefully available for linux-x64)
#
# For now this is left as manual step, as the normal user shouldn't have a need to recompile kernel parts on the Pi itself

# Set default defconfig
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- re4son_pi1_defconfig

# Enable ath9k_htc for AR9271-class adapters
scripts/config --module CONFIG_ATH9K_HTC
scripts/config --module CONFIG_ATH9K
scripts/config --module CONFIG_ATH9K_COMMON
scripts/config --module CONFIG_ATH9K_HW
scripts/config --module CONFIG_ATH
scripts/config --module CONFIG_MAC80211
scripts/config --module CONFIG_CFG80211
scripts/config --module CONFIG_RFKILL

make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- olddefconfig

# Build kernel
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j"${kernel_jobs}"

# Make kernel modules
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- modules_install INSTALL_MOD_PATH="${work_dir}"

# Copy kernel to boot
perl scripts/mkknlimg --dtok arch/arm/boot/zImage "${work_dir}"/boot/firmware/kernel.img
cp arch/arm/boot/dts/*.dtb "${work_dir}"/boot/firmware/
cp arch/arm/boot/dts/overlays/*.dtb* "${work_dir}"/boot/firmware/overlays/
cp arch/arm/boot/dts/overlays/README "${work_dir}"/boot/firmware/overlays/

make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- mrproper
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- re4son_pi1_defconfig
# kernver is used so we don't need to keep track of what the current compiled
# version is
kernver=$(ls "${work_dir}"/lib/modules/)
cd "${work_dir}"/lib/modules/"${kernver}"
rm build
rm source
ln -s /usr/src/kernel build
ln -s /usr/src/kernel source
cd "${base_dir}"

# git clone of nexmon moved in front of kernel compilation, to have poper brcmfmac driver ready
status 'Build nexmon firmware'
cd "${base_dir}"/nexmon

# Make sure we're not still using the armel cross compiler
unset CROSS_COMPILE

# Disable statistics
touch DISABLE_STATISTICS
source setup_env.sh

# The bundled b43 assembler links against the legacy AT&T lex library (-ll),
# which no longer ships on modern Debian/Ubuntu/Kali (only flex's -lfl exists).
# Switch it to -lfl so buildtools links instead of failing with
# "/usr/bin/ld: cannot find -ll".
sed -i -e 's/^LDFLAGS += -ll$/LDFLAGS += -lfl/' buildtools/b43/assembler/Makefile

make
cd buildtools/isl-0.10
CC=$CCgcc
./configure
make
sed -i -e 's/all:.*/all: $(RAM_FILE)/g' "${NEXMON_ROOT}"/patches/bcm43430a1/7_45_41_46/nexmon/Makefile
cd "${NEXMON_ROOT}"/patches/bcm43430a1/7_45_41_46/nexmon
make clean

# We do this so we don't have to install the ancient isl version into /usr/local/lib on systems
LD_LIBRARY_PATH="${NEXMON_ROOT}/buildtools/isl-0.10/.libs" make ARCH=arm CC="${NEXMON_ROOT}/buildtools/gcc-arm-none-eabi-5_4-2016q2-linux-x86/bin/arm-none-eabi-"

# RPi0w->3B firmware
# disable nexmon by default
mkdir -p "${work_dir}"/lib/firmware/brcm
cp "${NEXMON_ROOT}/patches/bcm43430a1/7_45_41_46/nexmon/brcmfmac43430-sdio.bin" "${work_dir}"/lib/firmware/brcm/brcmfmac43430-sdio.nexmon.bin
cp "${NEXMON_ROOT}/patches/bcm43430a1/7_45_41_46/nexmon/brcmfmac43430-sdio.bin" "${work_dir}"/lib/firmware/brcm/brcmfmac43430-sdio.bin
wget https://raw.githubusercontent.com/RPi-Distro/firmware-nonfree/master/brcm/brcmfmac43430-sdio.txt -O "${work_dir}"/lib/firmware/brcm/brcmfmac43430-sdio.txt

# Make a backup copy of the rpi firmware in case people don't want to use the nexmon firmware
# The firmware used on the RPi is not the same firmware that is in the firmware-brcm package which is why we do this
wget https://raw.githubusercontent.com/RPi-Distro/firmware-nonfree/master/brcm/brcmfmac43430-sdio.bin -O "${work_dir}"/lib/firmware/brcm/brcmfmac43430-sdio.rpi.bin

# Set hostname
status 'Set hostname'
echo "${hostname}" >"${work_dir}"/etc/hostname

cd "${repo_dir}/"

# Clean system
include clean_system

# Calculate the space to create the image and create
make_image

# Create the disk partitions
status "Create the disk partitions"
parted -s "${image_dir}/${image_name}.img" mklabel msdos
parted -s "${image_dir}/${image_name}.img" mkpart primary fat32 4MiB "${bootsize}"MiB
parted -s -a minimal "${image_dir}/${image_name}.img" mkpart primary "$fstype" "${bootsize}"MiB 100%

# Set the partition variables
make_loop

# Create file systems
mkfs_partitions

# Make fstab,
make_fstab

# Configure Raspberry Pi firmware
include rpi_firmware

status 'Configure Raspberry Pi boot settings'
grep -q '^enable_uart=1' "${work_dir}"/boot/firmware/config.txt || echo 'enable_uart=1' >> "${work_dir}"/boot/firmware/config.txt
grep -q '^dtoverlay=disable-bt' "${work_dir}"/boot/firmware/config.txt || echo 'dtoverlay=disable-bt' >> "${work_dir}"/boot/firmware/config.txt
grep -q '^dtoverlay=dwc2' "${work_dir}"/boot/firmware/config.txt || echo 'dtoverlay=dwc2' >> "${work_dir}"/boot/firmware/config.txt
sed -i -e 's/net.ifnames=0/net.ifnames=0 modules-load=dwc2/' "${work_dir}"/boot/firmware/cmdline.txt

# RaspberryPi devices mount the first partition on /boot/firmware
sed -i -e 's|/boot|/boot/firmware|' "${work_dir}"/etc/fstab

# Create the dirs for the partitions and mount them
status "Create the dirs for the partitions and mount them"
mkdir -p "${base_dir}"/root/

if [[ $fstype == ext4 ]]; then
    mount -t ext4 -o noatime,data=writeback,barrier=0 "${rootp}" "${base_dir}"/root

else
    mount "${rootp}" "${base_dir}"/root

fi

mkdir -p "${base_dir}"/root/boot/firmware
mount "${bootp}" "${base_dir}"/root/boot/firmware

status "Rsyncing rootfs into image file"
rsync -HPavz -q --exclude boot/firmware "${work_dir}"/ "${base_dir}"/root/
sync

status "Rsyncing rootfs into image file (/boot/firmware)"
rsync -rtx -q "${work_dir}"/boot/firmware "${base_dir}"/root/boot
sync

# Load default finish_image configs
include finish_image
