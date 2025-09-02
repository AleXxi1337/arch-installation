#!/bin/bash
set -euo pipefail

sbctl create-keys
sbctl sign -s \
  -o /usr/lib/systemd/boot/efi/systemd-bootx64.efi.signed \
  /usr/lib/systemd/boot/efi/systemd-bootx64.efi
sbctl enroll-keys --microsoft
sbctl sign -s /boot/EFI/Linux/arch-linux.efi
sbctl sign -s /boot/EFI/Linux/arch-linux-fallback.efi
sbctl sign -s /efi/EFI/systemd/systemd-bootx64.efi
sbctl sign -s /efi/EFI/Boot/bootx64.efi
sbctl verify

systemd-cryptenroll --tpm2-device=auto /dev/mapper/cryptroot --tpm2-pcrs=7