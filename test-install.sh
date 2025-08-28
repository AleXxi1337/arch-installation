#!/bin/bash
set -euo pipefail

export DISK=/dev/vda
export TIMEZONE=Europe/Moscow
export HOSTNAME=arch
export USERNAME=aboba
export ROOT_PASSWORD="rootpass"
export USER_PASSWORD="userpass"


export EFI="${DISK}1"
export CRYPTROOT="${DISK}2"

env \
    DISK="$DISK" \
    TIMEZONE="$TIMEZONE" \
    HOSTNAME="$HOSTNAME" \
    USERNAME="$USERNAME" \
    ROOT_PASSWORD="$ROOT_PASSWORD" \
    USER_PASSWORD="$USER_PASSWORD" \
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

# --- Initramfs ---
sed -i 's/^MODULES=.*/MODULES=(amdgpu f2fs)/' /etc/mkinitcpio.conf
sed -i 's/^HOOKS=.*/HOOKS=(base systemd keyboard autodetect microcode modconf kms sd-vconsole block sd-encrypt filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P || echo "❌ mkinitcpio упал с кодом $?"
echo "✅ Initramfs"

# --- ZRAM ---
tee /etc/systemd/zram-generator.conf > /dev/null <<ZRAM
[zram0]
zram-size = 2G
compression-algorithm = zstd
swap-priority = 100
ZRAM
echo "✅ ZRAM"

# --- GRUB + TPM ---
export CRYPTUUID=$(blkid -s UUID -o value "${DISK}2")
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"rd.luks.name=$CRYPTUUID=cryptroot root=/dev/mapper/cryptroot rootfstype=f2fs\"|" /etc/default/grub
echo "GRUB_ENABLE_CRYPTODISK=y" >> /etc/default/grub

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --modules="tpm"
grub-mkconfig -o /boot/grub/grub.cfg
echo "✅ GRUB + TPM"

# --- TPM в LUKS ---
systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 "${DISK}2"
echo "✅ TPM в LUKS"

# --- Secure Boot с sbctl ---
# 1. Создаём ключи
sbctl create-keys

# 2. Подписываем загрузчик и ядро
sbctl sign -s /boot/EFI/GRUB/grubx64.efi
sbctl sign -s /boot/vmlinuz-linux-zen

# 3. Вносим ключи в UEFI (с Microsoft для совместимости)
sbctl enroll-keys -m

# Проверка
sbctl status
echo "✅ Secure boot"

CHROOT_EOF

echo "✅ Установка завершена. Перезагружай систему!"
