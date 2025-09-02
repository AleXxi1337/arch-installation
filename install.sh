#!/bin/bash
set -euo pipefail

export DISK=/dev/sdX
export TIMEZONE=Europe/Moscow
export HOSTNAME=arch
export USERNAME=aboba
export ROOT_PASSWORD="rootpass"
export USER_PASSWORD="userpass"
export LUKS_PASSWORD="your_luks_password_here"

setfont cyr-sun16

# --- Разметка ---
echo -e 'label: gpt\nsize=1024M, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B\ntype=0FC63DAF-8483-4772-8E79-3D69D8477DE4' | sfdisk "$DISK"
echo "✅ Разметка выполнена"

export EFI="${DISK}1"
export CRYPTROOT="${DISK}2"

mkfs.fat -F32 $EFI

echo -n "$LUKS_PASSWORD" | cryptsetup luksFormat --type luks2 "$CRYPTROOT" -
echo -n "$LUKS_PASSWORD" | cryptsetup open "$CRYPTROOT" cryptroot -

mkfs.f2fs /dev/mapper/cryptroot

mount /dev/mapper/cryptroot /mnt
mkdir -p /mnt/boot
mount $EFI /mnt/boot

# --- Базовые пакеты + Secure Boot ---
sed -i "s/^#ParallelDownloads/ParallelDownloads/" /etc/pacman.conf
reflector --country Russia --protocol http,https --sort rate --save /etc/pacman.d/mirrorlist
pacstrap -K /mnt base base-devel linux-zen linux-firmware amd-ucode \
    sudo networkmanager cryptsetup vim man-db man-pages \
    sbctl f2fs-tools zram-generator
echo "✅ Установка завершена"

genfstab -U /mnt >> /mnt/etc/fstab
echo "✅ Fstab"

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

# --- Время и локаль ---
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
echo "✅ Время установлено"

sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
sed -i 's/^#\(ru_RU.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo "✅ Локали сгенерированы"

# --- Сеть и пользователи ---
echo "$HOSTNAME" > /etc/hostname
cat >/etc/hosts <<HST
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HST
systemctl enable NetworkManager
echo "✅ Сетевые настройки"

echo "root:$ROOT_PASSWORD" | chpasswd

useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$USER_PASSWORD" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo "✅ Пользователь создан и пароли установлены"

# --- vconsole ---
cat > /etc/vconsole.conf <<VC
FONT=cyr-sun16
KEYMAP=us
VC
echo "✅ /etc/vconsole.conf настроен"

# --- ZRAM ---
tee /etc/systemd/zram-generator.conf > /dev/null <<ZRAM
[zram0]
zram-size = 2G
compression-algorithm = zstd
swap-priority = 100
ZRAM
echo "✅ ZRAM"

# --- Initramfs ---
sed -i 's/^MODULES=.*/MODULES=(amdgpu f2fs tpm-tis)/' /etc/mkinitcpio.conf
sed -i 's/^HOOKS=.*/HOOKS=(base systemd keyboard autodetect microcode modconf kms sd-vconsole block sd-encrypt filesystems fsck)/' /etc/mkinitcpio.conf
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

PRESET_FILE="/etc/mkinitcpio.d/linux-zen.present"

sed -i 's|/efi|/boot|g' "$PRESET_FILE"
sed -i 's/^#\(default_uki=\)/\1/' "$PRESET_FILE
sed -i 's/^#\(fallback_uki=\)/\1/' "$PRESET_FILE

echo "✅ systemd-boot установлен и настроен"

CHROOT_EOF

echo "✅ Установка завершена. Перезагружай систему!"
