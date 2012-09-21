#!/bin/bash
# archstone
# ------------------------------------------------------------------------
# arch linux install script
# es@ethanschoonover.com @ethanschoonover
#
# scp this script into a system booted from Arch install media
# this version design for systems successfully booted using EFI

# ------------------------------------------------------------------------
# 0 ENVIRONMENT
# ------------------------------------------------------------------------
# language, fonts, keymaps, timezone

HOSTNAME=tau
FONT=Lat2-Terminus16
LANGUAGE=en_US.UTF-8
KEYMAP=us
TIMEZONE=US/Pacific
USERNAME=es # not used yet
USERSHELL=/bin/bash

MODULES="dm_mod dm_crypt aes_x86_64 ext2 ext4 vfat intel_agp drm i915"
HOOKS="usb usbinput consolefont encrypt filesystems"

# ------------------------------------------------------------------------
# 0 SCRIPT SETTINGS AND HELPER FUNCTIONS
# ------------------------------------------------------------------------

set -o nounset
set -o errexit

HR=-----------------------------------------------------------------------

SetValue () { VALUENAME="$1" NEWVALUE="$2" FILEPATH="$3"; 
sed -i "s+^#\?\(${VALUENAME}\)=.*$+\1=${NEWVALUE}+" "${FILEPATH}"; }

CommentOutValue () { VALUENAME="$1" FILEPATH="$2"; 
sed -i "s/^\(${VALUENAME}.*\)$/#\1/" "${FILEPATH}"; }

UncommentValue () { VALUENAME="$1" FILEPATH="$2"; 
sed -i "s/^#\(${VALUENAME}.*\)$/\1/" "${FILEPATH}"; }

AddToList () { NEWITEM="$1" LISTNAME="$2" FILEPATH="$3"; 
sed -i "s/\(${LISTNAME}.*\)\()\)/\1 ${NEWITEM}\2/" "${FILEPATH}"; }

GetUUID () {
VOLPATH="$1";
blkid ${DRIVE}${PARTITION_CRYPT_SWAP} \
| awk '{ print $2 }' \
| sed "s/UUID=\"\(.*\)\"/\1/";
}

Install () { pacman -S --noconfirm "$@"; }

AURInstall () {
if command -v packer >/dev/null 2>&1; then
packer -S --noconfirm "$@"
else
pkg=packer
orig="$(pwd)"; mkdir -p /tmp/${pkg}; cd /tmp/${pkg};
command -v wget >/dev/null 2>&1 || Install wget
command -v git >/dev/null 2>&1 || Install git
command -v jshon >/dev/null 2>&1 || Install jshon
wget "https://aur.archlinux.org/packages/${pkg}/${pkg}.tar.gz";
tar -xzvf ${pkg}.tar.gz; cd ${pkg}; makepkg --asroot -si --noconfirm;
cd "$orig"; rm -rf /tmp/${pkg}; 
packer -S --noconfirm "$@"
fi
}

AnyKey () { read -sn 1 -p "$@"; }

# ------------------------------------------------------------------------
# 1 PREFLIGHT
# ------------------------------------------------------------------------

setfont $FONT

# ------------------------------------------------------------------------
# 2 DRIVE
# ------------------------------------------------------------------------

DRIVE=/dev/sda
PARTITION_EFI_BOOT=1
PARTITION_CRYPT_SWAP=2
PARTITION_CRYPT_ROOT=3
LABEL_BOOT_EFI=bootefi
LABEL_SWAP=swap
LABEL_SWAP_CRYPT=cryptswap
LABEL_ROOT=root
LABEL_ROOT_CRYPT=cryptroot
MOUNT_PATH=/mnt
EFI_BOOT_PATH=/boot/efi

##########################################################################
# START FIRST RUN SECTION (PRE CHROOT)
##########################################################################

if [ `basename $0` != "postchroot.sh" ]; then

# ------------------------------------------------------------------------
# 3 FILESYSTEM
# ------------------------------------------------------------------------
# Here we create three partitions:
# 1. efi and /boot (one partition does double duty)
# 2. swap
# 3. our encrypted root
# Note that all of these are on a GUID partition table scheme. This proves
# to be quite clean and simple since we're not doing anything with MBR
# boot partitions and the like.

# disk prep
sgdisk -Z ${DRIVE} # zap all on disk
sgdisk -a 2048 -o ${DRIVE} # new gpt disk 2048 alignment

# create partitions
# (UEFI BOOT), default start block, 200MB
sgdisk -n ${PARTITION_EFI_BOOT}:0:+200M ${DRIVE}
# (SWAP), default start block, 2GB
sgdisk -n ${PARTITION_CRYPT_SWAP}:0:+2G ${DRIVE}
# (LUKS), default start, remaining space
sgdisk -n ${PARTITION_CRYPT_ROOT}:0:0 ${DRIVE}

# set partition types
sgdisk -t ${PARTITION_EFI_BOOT}:ef00 ${DRIVE}
sgdisk -t ${PARTITION_CRYPT_SWAP}:8200 ${DRIVE}
sgdisk -t ${PARTITION_CRYPT_ROOT}:8300 ${DRIVE}

# label partitions
sgdisk -c ${PARTITION_EFI_BOOT}:"${LABEL_BOOT_EFI}" ${DRIVE}
sgdisk -c ${PARTITION_CRYPT_SWAP}:"${LABEL_SWAP}" ${DRIVE}
sgdisk -c ${PARTITION_CRYPT_ROOT}:"${LABEL_ROOT}" ${DRIVE}

# format LUKS on root
cryptsetup --cipher=aes-xts-plain --verify-passphrase --key-size=512 \
luksFormat ${DRIVE}${PARTITION_CRYPT_ROOT}
cryptsetup luksOpen ${DRIVE}${PARTITION_CRYPT_ROOT} ${LABEL_ROOT_CRYPT}

# make filesystems
mkfs.vfat ${DRIVE}${PARTITION_EFI_BOOT}
mkfs.ext4 /dev/mapper/${LABEL_ROOT_CRYPT}

# mount target
# mkdir ${MOUNT_PATH}
mount /dev/mapper/${LABEL_ROOT_CRYPT} ${MOUNT_PATH}
mkdir -p ${MOUNT_PATH}${EFI_BOOT_PATH}
mount -t vfat ${DRIVE}${PARTITION_EFI_BOOT} ${MOUNT_PATH}${EFI_BOOT_PATH}

# install base system
pacstrap ${MOUNT_PATH} base base-devel

# ------------------------------------------------------------------------
# 4 BASE INSTALL
# ------------------------------------------------------------------------

# DEBUG: does this need to be here before install?
# kernel modules for EFI install
# ------------------------------------------------------------------------
modprobe efivars
modprobe dm-mod

pacstrap ${MOUNT_PATH} base base-devel

# ------------------------------------------------------------------------
# 5 FILESYSTEM
# ------------------------------------------------------------------------

# write to crypttab
# note: only /dev/disk/by-partuuid, /dev/disk/by-partlabel and
# /dev/sda2 formats work here
cat > ${MOUNT_PATH}/etc/crypttab <<CRYPTTAB_EOF
${LABEL_SWAP_CRYPT} /dev/disk/by-partlabel/${LABEL_SWAP} \
/dev/urandom swap,allow-discards
CRYPTTAB_EOF

# not using genfstab here since it doesn't record partlabel labels
cat > ${MOUNT_PATH}/etc/fstab <<FSTAB_EOF
# /etc/fstab: static file system information
#
# <file system>					<dir>		<type>	<options>				<dump>	<pass>
tmpfs						/tmp		tmpfs	nodev,nosuid				0	0
/dev/mapper/${LABEL_ROOT_CRYPT}			/      		ext4	rw,relatime,data=ordered,discard	0	1
/dev/disk/by-partlabel/${LABEL_BOOT_EFI}	$EFI_BOOT_PATH	vfat	rw,relatime,discard			0	2
/dev/mapper/${LABEL_SWAP_CRYPT}			none		swap	defaults,discard			0	0
FSTAB_EOF

# ------------------------------------------------------------------------
# 6 CHROOT
# ------------------------------------------------------------------------

# unmount EFI volume first (needs to be remounted post-chroot for grub)
umount ${MOUNT_PATH}${EFI_BOOT_PATH}

cp "$0" "${MOUNT_PATH}/postchroot.sh"
arch-chroot ${MOUNT_PATH} <<EOF
/postchroot.sh
EOF
exit
#echo -e "\narch-chroot ${MOUNT_PATH} then continue with /postchroot.sh"
#exit
fi



##########################################################################
# START SECOND RUN SECTION (POST CHROOT)
##########################################################################

# ------------------------------------------------------------------------
# remount efi boot volume
# ------------------------------------------------------------------------
# remount efi boot volume here or grub et al gets confused
mount -t vfat ${DRIVE}${PARTITION_EFI_BOOT} ${EFI_BOOT_PATH}

# ------------------------------------------------------------------------
# LANGUAGE
# ------------------------------------------------------------------------
UncommentValue ${LANGUAGE} /etc/locale.gen
locale-gen
echo LANG=${LANGUAGE} > /etc/locale.conf
export LANG=${LANGUAGE}
cat > /etc/vconsole.conf <<VCONSOLECONF
KEYMAP=${KEYMAP}
FONT=${FONT}
FONT_MAP=
VCONSOLECONF

# ------------------------------------------------------------------------
# TIME
# ------------------------------------------------------------------------
ln -s /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
echo ${TIMEZONE} >> /etc/timezone
hwclock --systohc --utc # set hardware clock
Install ntp
sed -i "/^DAEMONS/ s/hwclock /!hwclock @ntpd /" /etc/rc.conf

# ------------------------------------------------------------------------
# HOSTNAME
# ------------------------------------------------------------------------
echo ${HOSTNAME} > /etc/hostname
sed -i "s/localhost\.localdomain/${HOSTNAME}/g" /etc/hosts

# ------------------------------------------------------------------------
# NETWORK
# ------------------------------------------------------------------------
#Install wireless_tools netcfg wpa_supplicant wpa_actiond dialog
#AddToList net-auto-wireless DAEMONS /etc/rc.conf

Install iw wpa_supplicant wpa_actiond
AddToList net-auto-wireless DAEMONS /etc/rc.conf

# ------------------------------------------------------------------------
# RAMDISK
# ------------------------------------------------------------------------

# NOTE: intel_agp drm and i915 for intel graphics
sed -i "s/^MODULES.*$/MODULES=\"${MODULES}\"/" /etc/mkinitcpio.conf
sed -i "s/\(^HOOKS.*\) filesystems \(.*$\)/\1 ${HOOKS} \2/" \
/etc/mkinitcpio.conf

mkinitcpio -p linux

# ------------------------------------------------------------------------
# 9 BOOTLOADER
# ------------------------------------------------------------------------

set -o verbose

# we've already done this above... i need to remove one or the other
#set -e
#modprobe efivars
#modprobe dm-mod
#set +e

Install wget efibootmgr #gummiboot-efi-x86_64
AURInstall gummiboot-efi-x86_64 #gummiboot in extra now
install -Dm0644 /usr/lib/gummiboot/gummiboot.efi \
/boot/efi/EFI/arch/gummiboot.efi
install -Dm0644 /usr/lib/gummiboot/gummiboot.efi \
/boot/efi/EFI/boot/bootx64.efi
efibootmgr -c -l '\EFI\arch\gummiboot.efi\' -L "Arch Linux"
cp /boot/vmlinuz-linux /boot/efi/EFI/arch/vmlinuz-linux.efi
cp /boot/initramfs-linux.img /boot/efi/EFI/arch/initramfs-linux.img
cp /boot/initramfs-linux-fallback.img \
/boot/efi/EFI/arch/initramfs-linux-fallback.img
mkdir -p ${EFI_BOOT_PATH}/loader/entries
cat >> ${EFI_BOOT_PATH}/loader/default.conf <<GUMMILOADER
default arch
timeout 4
GUMMILOADER
cat >> ${EFI_BOOT_PATH}/loader/entries/arch.conf <<GUMMIENTRIES
title          Arch Linux
efi            \\EFI\\arch\\vmlinuz-linux.efi
options        initrd=\\EFI\\arch\initramfs-linux.img \
cryptdevice=/dev/sda3:${LABEL_ROOT_CRYPT} \
root=/dev/mapper/${LABEL_ROOT_CRYPT} ro rootfstype=ext4 
GUMMIENTRIES








# ------------------------------------------------------------------------
# 10 POSTFLIGHT CUSTOMIZATIONS
# ------------------------------------------------------------------------
# functions (these could be a library, but why overcomplicate things
# ------------------------------------------------------------------------

# root password
# ------------------------------------------------------------------------
echo -e "${HR}\\nNew root user password\\n${HR}"
passwd

# add user
# ------------------------------------------------------------------------
echo -e "${HR}\\nNew non-root user password (username:${USERNAME})\\n${HR}"
groupadd sudo
useradd -m -g users -G audio,lp,optical,storage,video,games,power,scanner,network,sudo,wheel -s ${USERSHELL} ${USERNAME}
passwd ${USERNAME}

# mirror ranking
# ------------------------------------------------------------------------
#echo -e "${HR}\\nRanking Mirrors (this will take a while)\\n${HR}"
#cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.orig
#mv /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.all
#sed -i "s/#S/S/" /etc/pacman.d/mirrorlist.all
#rankmirrors -n 5 /etc/pacman.d/mirrorlist.all > /etc/pacman.d/mirrorlist

# mirrors - all (quick and dirty alternate to ranking)
# ------------------------------------------------------------------------
#cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.orig
#sed -i "s/#S/S/" /etc/pacman.d/mirrorlist

# temporary fix for locale.sh update conflict
# ------------------------------------------------------------------------
#mv /etc/profile.d/locale.sh /etc/profile.d/locale.sh.preupdate || true

# additional groups and utilities
# ------------------------------------------------------------------------
#pacman --noconfirm -Syu
#pacman --noconfirm -S base-devel

# sudo
# ------------------------------------------------------------------------
Install sudo
cp /etc/sudoers /tmp/sudoers.edit
sed -i "s/#\s*\(%wheel\s*ALL=(ALL)\s*ALL.*$\)/\1/" /tmp/sudoers.edit
sed -i "s/#\s*\(%sudo\s*ALL=(ALL)\s*ALL.*$\)/\1/" /tmp/sudoers.edit
visudo -qcsf /tmp/sudoers.edit && cat /tmp/sudoers.edit > /etc/sudoers 

# power
# ------------------------------------------------------------------------
Install acpi acpid cpupower powertop
#sed -i "/^DAEMONS/ s/)/ @acpid)/" /etc/rc.conf
#sed -i "/^MODULES/ s/)/ acpi-cpufreq cpufreq_ondemand cpufreq_powersave coretemp)/" /etc/rc.conf
# following requires my acpi handler script
#echo "/etc/acpi/handler.sh boot" > /etc/rc.local
#TODO: https://wiki.archlinux.org/index.php/Acpi - review this

# wireless (wpa supplicant should already be installed)
# ------------------------------------------------------------------------
Install iw wpa_supplicant rfkill
Install netcfg wpa_actiond ifplugd
mv /etc/wpa_supplicant.conf /etc/wpa_supplicant.conf.orig
echo -e "ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=network\nupdate_config=1" > /etc/wpa_supplicant.conf
# make sure to copy /etc/network.d/examples/wireless-wpa-config to /etc/network.d/home and edit
sed -i "/^DAEMONS/ s/)/ @net-auto-wireless @net-auto-wired)/" /etc/rc.conf
sed -i "/^DAEMONS/ s/ network / /" /etc/rc.conf
echo -e "\nWIRELESS_INTERFACE=wlan0" >> /etc/rc.conf
echo -e "WIRED_INTERFACE=eth0" >> /etc/rc.conf
echo "options iwlagn led_mode=2" > /etc/modprobe.d/iwlagn.conf
#TODO: should this now be in /etc/modules-load.d?

# sound
# ------------------------------------------------------------------------
Install alsa-utils alsa-plugins
sed -i "/^DAEMONS/ s/)/ @alsa)/" /etc/rc.conf
mv /etc/asound.conf /etc/asound.conf.orig || true
#if alsamixer isn't working, try alsamixer -Dhw and speaker-test -Dhw -c 2

NOTYET () {

# video
# ------------------------------------------------------------------------
Install base-devel mesa mesa-demos # linux-headers

# x
# ------------------------------------------------------------------------
Install xorg xorg-server xorg-xinit xorg-utils xorg-server-utils xdotool xorg-xlsfonts
Install xf86-input-wacom
#AURInstall xf86-input-wacom-git

# environment/wm/etc.
# ------------------------------------------------------------------------
#Install xfce4 compiz ccsm
Install xcompmgr xscreensaver hsetroot
Install rxvt-unicode urxvt-url-select
AURInstall rxvt-unicode-cvs # need to manually edit out patch lines
Install urxvt-url-select
Install gtk2
Install ghc alex happy gtk2hs-buildtools cabal-install
AURInstall physlock
Install unclutter #TODO: consider hhp from xmonad-utils instead
Install dbus upower
sed -i "/^DAEMONS/ s/)/ @dbus)/" /etc/rc.conf

# TODO: another install script for this
# following as non root user, make sure \$HOME/.cabal/bin is in path
# make sure to nuke existing .ghc and .cabal directories first
#su ${USERNAME}
#cd \$HOME
#rm -rf \$HOME/.ghc \$HOME/.cabal
# TODO: consider adding just .cabal to the path as well
#export PATH=$PATH:\$HOME/.cabal/bin
#cabal update
# # NOT USING following line... alex, happy and gtk2hs-buildtools installed via paman
# # cabal install alex happy xmonad xmonad-contrib gtk2hs-buildtools
#cabal install xmonad xmonad-contrib taffybar
#cabal install c2hs language-c x11-xft xmobar --flags "all-extensions"
Install wireless_tools # don't want it, but xmobar does
#note that I installed xmobar from github instead
#exit

# fonts
# ------------------------------------------------------------------------
Install terminus-font
AURInstall webcore-fonts
AURInstall libspiro
AURInstall fontforge
packer -S freetype2-git-infinality # will prompt for freetype2 replacement
# TODO: sed infinality and change to OSX or OSX2 mode
#	and create the sym link from /etc/fonts/conf.avail to conf.d

# misc apps
# ------------------------------------------------------------------------
Install htop openssh keychain bash-completion git vim
Install chromium flashplugin
Install scrot mypaint bc
AURInstall task-git
AURInstall stellarium
# googlecl discovery requires the svn googlecl version and google-api-python-client and httplib2, gflags
AURInstall googlecl-svn
AURInstall googlecl-svn python2-google-api-python-client python2-httplib2 python2-gflags python-simplejson
#AURInstall google-talkplugin
AURInstall argyll dispcalgui
# TODO: argyll

# extras
# ------------------------------------------------------------------------

AURInstall haskell-mtl haskell-hscolour haskell-x11
AURInstall xmonad-darcs xmonad-contrib-darcs xmobar-git
AURInstall trayer-srg-git
#skype
Install zip # for pent buftabs
#AURInstall aurora
#AURInstall aurora-pentadactyl-buftabs-git
#AURInstall terminus-font-ttf
mkdir -p /home/${USERNAME}/.pentadactyl/plugins && ln -sf /usr/share/aurora-pentadactyl-buftabs/buftabs.js /home/${USERNAME}/.pentadactyl/plugins/buftabs.js

}

#EOF

#umount $EFI_BOOT_PATH
#exit
