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

# --- TPM в LUKS ---
echo -n "$LUKS_PASSWORD" | systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 "$CRYPTROOT"
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
