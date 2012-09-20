archstone
=========

##Arch Linux Lightweight Install Script

In its current form this is an effective but dangerous install script. It will immediately nuke your /dev/sda and it won't apologize for doing so. *Don't run this if that freaks you out.*

Right now this is purpose built to install Arch to an EFI system with a single drive. It sets it up as follows:

1. Erases drive
2. Setups an EFI boot paritition
3. Creates an encrypted / (root) and swap partition (no separate /home partition in this iteration)
4. Installs Arch to the encrypted root

Note that half way through the script you will have to run `arch-chroot /mnt` and then execute /postchroot.sh (I'm debugging why arch-chroot doesn't like to properly execute the script I send it).

Ethan es@ethanschoonover.com
