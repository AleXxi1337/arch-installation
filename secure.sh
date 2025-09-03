#!/bin/bash
set -euo pipefail

sbctl create-keys
sbctl sign -s \
  -o /usr/lib/systemd/boot/efi/systemd-bootx64.efi.signed \
  /usr/lib/systemd/boot/efi/systemd-bootx64.efi
sbctl enroll-keys --microsoft
sbctl sign -s /boot/EFI/Linux/arch-linux-zen.efi
sbctl sign -s /boot/EFI/Linux/arch-linux-zen-fallback.efi
sbctl sign -s /boot/EFI/systemd/systemd-bootx64.efi
sbctl sign -s /boot/EFI/Boot/bootx64.efi

systemd-cryptenroll --recovery-key /dev/vda2
systemd-cryptenroll --tpm2-device=auto /dev/vda2 --tpm2-pcrs=7