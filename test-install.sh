#!/bin/bash
set -euo pipefail

export DISK=/dev/sdX
export TIMEZONE=Europe/Moscow
export HOSTNAME=arch
export USERNAME=aboba
export ROOT_PASSWORD="rootpass"
export USER_PASSWORD="userpass"
export LUKS_PASSWORD="your_luks_password_here"

export EFI="${DISK}1"
export CRYPTROOT="${DISK}2"

setfont cyr-sun16

env \
    DISK="$DISK" \
    TIMEZONE="$TIMEZONE" \
    HOSTNAME="$HOSTNAME" \
    USERNAME="$USERNAME" \
    ROOT_PASSWORD="$ROOT_PASSWORD" \
    USER_PASSWORD="$USER_PASSWORD" \
    LUKS_PASSWORD="$LUKS_PASSWORD" \
    arch-chroot /mnt /bin/bash <<'CHROOT_EOF'
set -euo pipefail

# --- Initramfs ---
sed -i 's/^MODULES=.*/MODULES=(amdgpu f2fs tpm-tis)/' /etc/mkinitcpio.conf
sed -i 's/^HOOKS=.*/HOOKS=(base systemd keyboard autodetect microcode modconf kms sd-vconsole block sd-encrypt filesystems fsck)/' /etc/mkinitcpio.conf

PRESET_FILE="/etc/mkinitcpio.d/linux-zen.preset"

sed -i 's|/efi|/boot|g' "$PRESET_FILE"
sed -i 's/^#\(default_uki=\)/\1/' "$PRESET_FILE"
sed -i 's/^#\(fallback_uki=\)/\1/' "$PRESET_FILE"

mkinitcpio -P
echo "✅ Initramfs"

# --- systemd-boot ---
bootctl install

UUID=$(blkid -s UUID -o value ${DISK}2)

cat > /boot/loader/loader.conf <<LDR
default arch.conf
timeout 3
console-mode auto
editor no
LDR

cat > /boot/loader/entries/arch.conf <<ENTRY
title   Arch Linux
linux   /vmlinuz-linux-zen
initrd  /amd-ucode.img
initrd  /initramfs-linux-zen.img
options rd.luks.name=${UUID}=cryptroot root=/dev/mapper/cryptroot rw
ENTRY

echo "✅ systemd-boot установлен и настроен"

CHROOT_EOF

echo "✅ Установка завершена. Перезагружай систему!"
