#!/bin/bash

prepare() {
  sed -i s/^"#de_DE.UTF-8 UTF-8"/"de_DE.UTF-8 UTF-8"/g /etc/locale.gen
  sed -i s/^"#en_US.UTF-8 UTF-8"/"en_US.UTF-8 UTF-8"/g /etc/locale.gen
  locale-gen

  # Wipe all partitions
  wipefs --all ${DISK}
}

partition_unencrypted() {
  PARTITION=${DISK}p1

  parted ${DISK} mklabel gpt
  parted ${DISK} mkpart primary 1 100%
  mkfs.ext4 ${PARTITION}
  mount ${PARTITION} /mnt

  export ENCYPTION="none" 
}

partition_encrypted() {
  BOOT_PARTITION=${DISK}p1
  ROOT_PARTITION=${DISK}p2

  parted ${DISK} mklabel gpt 
  parted ${DISK} mkpart primary fat32 1MiB 265MiB
  parted ${DISK} set 1 esp on
  parted ${DISK} mkpart primary ext4 265MiB 100%

  dd if=/dev/urandom of=${ROOT_PARTITION} bs=512 count=40960
  cryptsetup luksFormat ${ROOT_PARTITION}
  cryptsetup --type luks open ${ROOT_PARTITION} root

  mkfs.fat -F 32 ${BOOT_PARTITION}
  mkfs.ext4 /dev/mapper/root

  mount /dev/mapper/root /mnt
  mkdir /mnt/boot
  mount ${BOOT_PARTITION} /mnt/boot

  export ROOT_UUID=`blkid -s UUID -o value ${ROOT_PARTITION}`
  export ENCYPTION="full"
}

install_bootstrap() {
  pacstrap /mnt base
  genfstab -U /mnt >> /mnt/etc/fstab

  arch-chroot /mnt /bin/bash -x <<'EOF'
  pacman -Sy --quiet --noconfirm linux efibootmgr sudo

  # Setup user and password
  echo "root:${PASSWORD}" | chpasswd
  groupadd ${USERNAME}
  useradd --create-home --gid ${USERNAME} --groups wheel --shell /bin/bash ${USERNAME}
  echo "${USERNAME}:${PASSWORD}" | chpasswd

  # Setup locales/timezone
  sed -i s/^"#de_DE.UTF-8 UTF-8"/"de_DE.UTF-8 UTF-8"/g /etc/locale.gen
  sed -i s/^"#en_US.UTF-8 UTF-8"/"en_US.UTF-8 UTF-8"/g /etc/locale.gen
  locale-gen
  echo LANG=en_US.UTF-8 > /etc/locale.conf
  echo "KEYMAP=de" > /etc/vconsole.conf

  # Setup sudoers
  sed -i '/%wheel ALL=(ALL) ALL/s/^#//' /etc/sudoers

  if [[ -e "/etc/localtime" ]]; then
    rm -rf /etc/localtime
  fi

  ln -s /usr/share/zoneinfo/Europe/Berlin /etc/localtime

  hwclock --systohc --utc

  # Setup hostname
  echo ${HOSTNAME} > /etc/hostname
EOF
}

install_bootloader() {
  arch-chroot /mnt /bin/bash -x <<'EOF'
    # Basic stuff
    pacman -Sy --quiet --noconfirm grub

    # Adjust grub/initcpio
    if [ "${ENCYPTION}" == "full" ]; then
      sed -i s/^GRUB_CMDLINE_LINUX=\"\"/GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=${ROOT_UUID}:root\"/g /etc/default/grub
      sed -i s/^HOOKS.*/HOOKS="\"base udev autodetect modconf block keymap encrypt filesystems keyboard fsck"\"/g /etc/mkinitcpio.conf
    mkinitcpio -p linux
    fi

    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
    grub-mkconfig -o /boot/grub/grub.cfg
EOF
}

install_base() {
  arch-chroot /mnt /bin/bash -x <<'EOF'
  # Basic stuff
  pacman -Sy --quiet --noconfirm vim bash-completion

  # Xorg
  pacman -Sy --quiet --noconfirm xorg-server

  # Fonts
  pacman -Sy --quiet --noconfirm ttf-dejavu
  # pacman -Sy --quiet --noconfirm ttf-liberation
  # pacman -Sy --quiet --noconfirm noto-fonts
  # pacman -Sy --quiet --noconfirm ttf-croscore  
EOF
}

install_base_notebook() {
  arch-chroot /mnt /bin/bash -x <<'EOF'
    # Notebook stuff
    pacman -Sy --quiet --noconfirm intel-ucode
EOF
}

install_base_gnome() {
  arch-chroot /mnt /bin/bash -x <<'EOF'
    # GNOME
    pacman -Sy --quiet --noconfirm baobab cheese eog evince file-roller gdm gnome-backgrounds gnome-calculator gnome-calendar gnome-characters gnome-clocks gnome-color-manager gnome-contacts gnome-control-center gnome-dictionary gnome-disk-utility gnome-font-viewer gnome-keyring gnome-logs gnome-maps gnome-menus gnome-photos gnome-screenshot gnome-session gnome-settings-daemon gnome-shell gnome-shell-extensions gnome-system-monitor gnome-terminal gnome-todo gnome-weather gnome-tweaks gvfs gvfs-goa gvfs-google gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-smb mousetweaks mutter nautilus networkmanager simple-scan sushi totem xdg-user-dirs-gtk

    # Utilities
    pacman -Sy --quiet --noconfirm acpi_call cups cups-pdf ntfs-3g openssh pwgen rsync tlp tlp-rdw wget x86_energy_perf_policy alsa-utils

    systemctl enable org.cups.cupsd.service
    systemctl enable tlp

    systemctl enable gdm.service
    systemctl enable NetworkManager.service

    # See https://bugs.archlinux.org/task/63706?project=1&string=systemd
    chage -M -1 gdm
EOF
}

main() {
  read -p "Enter disk [/dev/nvme0n1]: " DISK
  read -p "Enter hostname: " HOSTNAME
  read -p "Enter username: " USERNAME
  read -s -p "Enter password: " PASSWORD
  echo ""

  DISK=${DISK:-/dev/nvme0n1}

  export HOSTNAME
  export USERNAME
  export PASSWORD
  export DISK

  ## Prepare
  prepare
  partition_encrypted
  # partition_unencrypted
  install_bootstrap
  install_bootloader
  install_base
  # install_base_notebook
  install_base_gnome
  ## Finish

  umount -R /mnt
  cryptsetup close root

  echo "Installation finished!"
}

main
