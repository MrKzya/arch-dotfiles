#!/usr/bin/env bash
# ArchT2 post-archinstall bootstrap for an Intel Mac with Apple T2.
# Run as root INSIDE the installed Arch system (arch-chroot), BEFORE rebooting.
# Scope: T2 kernel, boot-critical modules, a dedicated ESP, and basic services.
# No disk partitioning, formatting, dotfiles, or automatic reboot.
set -Eeuo pipefail

VERSION='0.1.0'
MIRROR='https://mirror.funami.tech/arch-mact2/os/x86_64'
GRUB_FILE='/etc/default/grub'
MKINIT_FILE='/etc/mkinitcpio.conf'
LOG_FILE='/var/log/macos-t2-setup.log'
MODE="${1:-}"

say()  { printf '\n\033[1;36m[t2]\033[0m %s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<USAGE
macos-t2.sh v${VERSION}
  bash macos-t2.sh          show the plan, confirm, then install
  bash macos-t2.sh --check  preflight only; do not change anything
  bash macos-t2.sh --help   show this help

Run inside arch-chroot after archinstall, while booted from ArchT2 ISO.
Requires a DEDICATED FAT32 EFI partition mounted at /boot, /boot/efi, or /efi.
Supports GRUB + mkinitcpio (not systemd-boot, UKI, or encrypted-root setups).
USAGE
}

case "$MODE" in
    --help|-h) usage; exit 0 ;;
    ''|--check) ;;
    *) usage; die "Unknown argument: $MODE" ;;
esac

[[ $EUID -eq 0 ]] || die 'Run as root in arch-chroot (no sudo needed there).'
[[ -r /etc/os-release ]] || die 'Missing /etc/os-release.'
# shellcheck disable=SC1091
source /etc/os-release
[[ ${ID:-} == arch ]] || die "Expected installed Arch Linux (detected ${ID:-unknown})."
[[ $(uname -m) == x86_64 ]] || die 'This script supports only Intel x86_64 Macs.'
[[ -d /sys/firmware/efi ]] || die 'System is not booted in UEFI mode.'
[[ -f /etc/fstab ]] || die 'Missing /etc/fstab. Finish archinstall first.'
grep -Eq '^[^#].*[[:space:]]/[[:space:]]' /etc/fstab || die 'No / entry in fstab; is this the installed system?'
[[ -r /sys/class/dmi/id/sys_vendor ]] || die 'DMI data unavailable. Is /sys mounted in arch-chroot?'
[[ $(< /sys/class/dmi/id/sys_vendor) == 'Apple Inc.' ]] || die 'This does not appear to be Apple hardware.'

for command in pacman findmnt lsblk readlink grub-mkconfig grub-install mkinitcpio systemctl; do
    command -v "$command" >/dev/null 2>&1 || die "Missing '$command'. In archinstall select GRUB and mkinitcpio."
done

# Refuse other kernels: with multiple kernels GRUB default may not be linux-t2.
for kernel in linux-lts linux-zen linux-hardened linux-xanmod; do
    if pacman -Qq "$kernel" >/dev/null 2>&1; then
        die "Found $kernel. v1 supports archinstall's standard linux kernel only."
    fi
done

[[ -f "$MKINIT_FILE" ]] || die "No $MKINIT_FILE. This script supports mkinitcpio only."
[[ -f "$GRUB_FILE" ]] || die "No $GRUB_FILE. In archinstall select GRUB (no UKI)."
[[ ! -f /etc/crypttab.initramfs ]] || die 'Encrypted-root config detected; v1 does not support LUKS.'
if [[ -f /etc/crypttab ]] && grep -Eq '^[[:space:]]*[^#[:space:]]' /etc/crypttab; then
    die 'Encrypted-root config detected; v1 does not support LUKS.'
fi

# Match an actual FAT32 mount, never an ordinary directory under /.
ESP_MOUNT=''
ESP_DEV=''
for candidate in /boot /boot/efi /efi; do
    if findmnt -rn -M "$candidate" -o FSTYPE 2>/dev/null | grep -Eq '^(vfat|fat|msdos)$'; then
        ESP_MOUNT="$candidate"
        ESP_DEV="$(findmnt -rn -M "$candidate" -o SOURCE)"
        break
    fi
done
[[ -n "$ESP_MOUNT" && -n "$ESP_DEV" ]] || die 'Dedicated FAT32 EFI partition not mounted at /boot, /boot/efi, or /efi.'
ESP_DEV="$(readlink -f "$ESP_DEV")"
[[ -b "$ESP_DEV" ]] || die "ESP source $ESP_DEV is not a block device."
ESP_KIND="$(lsblk -dn -o TYPE "$ESP_DEV" | head -n 1)"
[[ "$ESP_KIND" == part ]] || die "ESP source $ESP_DEV is not a partition."
ESP_PARTNUM="$(lsblk -dn -o PARTN "$ESP_DEV" | head -n 1)"
# Mac factory ESP is normally partition 1. Never touch it in a dual-boot setup.
[[ "$ESP_PARTNUM" != 1 ]] || die "Refusing partition #1 ($ESP_DEV): likely Apple's original EFI."
[[ ! -d "$ESP_MOUNT/EFI/APPLE" && ! -d "$ESP_MOUNT/EFI/Apple" ]] || die "Apple EFI files detected on $ESP_MOUNT. Refusing."
[[ ! -d "$ESP_MOUNT/EFI/Microsoft" ]] || die "Microsoft EFI files detected on $ESP_MOUNT. Refusing."
ESP_SIZE="$(lsblk -dn -o SIZE "$ESP_DEV" | head -n 1)"
ESP_LABEL="$(lsblk -dn -o LABEL "$ESP_DEV" | head -n 1)"

say "ArchT2 setup v${VERSION} — preflight"
info "Mac:            $(< /sys/class/dmi/id/product_name)"
info "EFI mount:      $ESP_MOUNT"
info "EFI partition:  $ESP_DEV (${ESP_SIZE}, label: ${ESP_LABEL:-none})"
info "Arch root:      $(findmnt -rn -M / -o SOURCE 2>/dev/null || printf 'unknown')"
info 'Bootloader:     GRUB (removable EFI, no NVRAM changes)'
info 'Kernel:         linux-t2 (stock linux removed ONLY after successful T2 initramfs)'
info 'Network:        NetworkManager + iwd'
info 'Other:          apple-bcm-firmware-fetcher, audio config, t2fanrd'
warn 'A separate EFI cannot be identified with 100% certainty automatically.'
warn 'Compare the above partition with lsblk and macOS Disk Utility.'
warn 'The [arch-mact2] repository uses SigLevel=Never per T2Linux docs (unsigned packages).'
warn 'Wi-Fi firmware may still need to be extracted from macOS after first boot.'

if [[ "$MODE" == --check ]]; then
    say 'CHECK PASSED. No files changed.'
    exit 0
fi

printf '\nType the EXACT EFI device (%s) to proceed: ' "$ESP_DEV"
read -r CONFIRMED_DEV
[[ "$CONFIRMED_DEV" == "$ESP_DEV" ]] || die 'Confirmation mismatch; nothing changed.'

# Log only after the user explicitly approved writes.
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'code=$?; warn "Stopped at line $LINENO (exit $code). Do NOT reboot until checked. Log: $LOG_FILE"; exit "$code"' ERR

say '1/6 — Configure T2 repository'
if ! grep -Eq '^[[:space:]]*\[arch-mact2\][[:space:]]*$' /etc/pacman.conf; then
    [[ -e /etc/pacman.conf.pre-macos-t2 ]] || cp -a /etc/pacman.conf /etc/pacman.conf.pre-macos-t2
    cat >> /etc/pacman.conf <<REPO

# T2Linux packages: https://wiki.t2linux.org/distributions/arch/faq/
[arch-mact2]
Server = ${MIRROR}
SigLevel = Never
REPO
else
    info 'Existing [arch-mact2] section found; not modifying it.'
fi

say '2/6 — Install T2 kernel and basic hardware support'
pacman -Syu --needed \
    linux-t2 linux-t2-headers linux-firmware \
    apple-t2-audio-config apple-bcm-firmware-fetcher t2fanrd \
    grub networkmanager iwd

[[ -s /boot/vmlinuz-linux-t2 ]] || die 'T2 kernel missing at /boot/vmlinuz-linux-t2. Is /boot correct?'
[[ -f /etc/mkinitcpio.d/linux-t2.preset ]] || die 'Missing linux-t2 mkinitcpio preset; cannot verify initramfs.'

say '3/6 — Configure early T2 keyboard modules and initramfs'
[[ -e "$MKINIT_FILE.pre-macos-t2" ]] || cp -a "$MKINIT_FILE" "$MKINIT_FILE.pre-macos-t2"
if grep -Eq '^[[:space:]]*MODULES=\([^)]*\)' "$MKINIT_FILE"; then
    original="$(sed -nE 's/^[[:space:]]*MODULES=\(([^)]*)\).*/\1/p' "$MKINIT_FILE" | head -n 1)"
else
    original=''
    printf '\nMODULES=()\n' >> "$MKINIT_FILE"
fi
modules="${original}"
for module in t2bce_dma t2bce_core t2bce_vhci; do
    if [[ " ${modules} " != *" ${module} "* ]]; then
        modules="${modules:+${modules} }${module}"
    fi
done
# Replace only the first active MODULES=(...) declaration.
sed -i -E "0,/^[[:space:]]*MODULES=\([^)]*\)/s|^[[:space:]]*MODULES=\([^)]*\)|MODULES=(${modules})|" "$MKINIT_FILE"
install -d -m 755 /etc/modules-load.d
printf 't2bce_vhci\n' > /etc/modules-load.d/t2.conf
# Stock 'linux' does not contain T2 modules; build ONLY the T2 preset here.
# A global mkinitcpio -P could fail on the temporary stock kernel.
mkinitcpio -p linux-t2
[[ -s /boot/initramfs-linux-t2.img ]] || die 'T2 initramfs missing; stock kernel retained.'

say '4/6 — Configure GRUB parameters'
[[ -e "$GRUB_FILE.pre-macos-t2" ]] || cp -a "$GRUB_FILE" "$GRUB_FILE.pre-macos-t2"
if grep -Eq '^GRUB_CMDLINE_LINUX="[^"]*"' "$GRUB_FILE"; then
    cmdline="$(sed -nE 's/^GRUB_CMDLINE_LINUX="([^"]*)".*/\1/p' "$GRUB_FILE" | head -n 1)"
else
    cmdline=''
fi
for arg in intel_iommu=on iommu=pt pm_async=off; do
    [[ " ${cmdline} " == *" ${arg} "* ]] || cmdline="${cmdline:+${cmdline} }${arg}"
done
if grep -Eq '^GRUB_CMDLINE_LINUX=' "$GRUB_FILE"; then
    sed -i -E "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"${cmdline}\"|" "$GRUB_FILE"
else
    printf '\nGRUB_CMDLINE_LINUX="%s"\n' "$cmdline" >> "$GRUB_FILE"
fi
if grep -Eq '^GRUB_DEFAULT=' "$GRUB_FILE"; then
    sed -i -E 's|^GRUB_DEFAULT=.*|GRUB_DEFAULT=0|' "$GRUB_FILE"
else
    printf 'GRUB_DEFAULT=0\n' >> "$GRUB_FILE"
fi

say '5/6 — Enable services'
install -d -m 755 /etc/NetworkManager/conf.d
if [[ ! -e /etc/NetworkManager/conf.d/90-t2-iwd.conf ]]; then
    cat > /etc/NetworkManager/conf.d/90-t2-iwd.conf <<'IWD'
[device]
wifi.backend=iwd
IWD
fi
systemctl enable NetworkManager.service iwd.service t2fanrd.service

say '6/6 — Install GRUB ONLY on the confirmed dedicated ESP'
# Back up the old fallback loader on the *confirmed dedicated* ESP, if present.
if [[ -f "$ESP_MOUNT/EFI/BOOT/BOOTX64.EFI" && ! -e "$ESP_MOUNT/EFI/BOOT/BOOTX64.EFI.pre-macos-t2" ]]; then
    cp -p "$ESP_MOUNT/EFI/BOOT/BOOTX64.EFI" "$ESP_MOUNT/EFI/BOOT/BOOTX64.EFI.pre-macos-t2"
fi
grub-install --target=x86_64-efi --efi-directory="$ESP_MOUNT" \
    --bootloader-id=ArchT2 --no-nvram --removable
grub-mkconfig -o /boot/grub/grub.cfg
[[ -s "$ESP_MOUNT/EFI/BOOT/BOOTX64.EFI" ]] || die 'GRUB fallback EFI loader not found.'
grep -Fq 'vmlinuz-linux-t2' /boot/grub/grub.cfg || die 'GRUB config does not reference linux-t2.'

# Only now, with both the bootloader and T2 GRUB entry verified, remove
# the temporary stock kernel so GRUB's default entry actually uses T2.
if pacman -Qq linux >/dev/null 2>&1; then
    info 'EFI loader and T2 GRUB entry verified; removing temporary stock linux.'
    pacman -R --noconfirm linux
    grub-mkconfig -o /boot/grub/grub.cfg
    grep -Fq 'vmlinuz-linux-t2' /boot/grub/grub.cfg || die 'T2 entry missing after removing stock linux.'
fi

say 'SUCCESS — the files for a first T2 boot are present.'
info 'No reboot was performed. Exit arch-chroot, then confirm the checklist with me.'
info "Log: $LOG_FILE"
info 'At startup, hold Option (Alt) and select EFI Boot (the Linux ESP).'
info 'After boot: uname -r; localectl status; systemctl status NetworkManager; lsmod | grep t2bce'
info 'If Wi-Fi is missing, firmware extraction is a separate step; do not change macOS partitions.'
