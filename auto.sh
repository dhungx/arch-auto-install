#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
set -o errtrace
# Arch + Hyprland Invincible-Dots – FIXED V3 (2025)

LOG=/tmp/arch-install-v3.log
rm -f "$LOG" || true; touch "$LOG"
exec > >(tee -a "$LOG") 2>&1

err_report(){
    local rc=$?
    echo -e "\n[✗] Lỗi xảy ra tại dòng ${BASH_LINENO[0]} (exit ${rc}). Xem log: $LOG" >&2
    echo "--- TAIL $LOG (last 200 lines) ---" >&2
    tail -n 200 "$LOG" >&2 || true
}
trap err_report ERR

# COLORS & helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'
info(){ echo -e "${GREEN}[+]${NC} $*"; }
warn(){ echo -e "${YELLOW}[!]${NC} $*"; }
error(){ echo -e "${RED}[✗]${NC} $*"; exit 1; }

cleanup() {
umount -R /mnt 2>/dev/null || true
swapoff -a 2>/dev/null || true
}
trap cleanup EXIT

[[ $EUID -ne 0 ]] && error "Chạy script với root trên ArchISO! (Run as root)"

clear
echo -e "${MAGENTA}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║   Arch + Hyprland Invincible-Dots - FIXED V3 2025    ║${NC}"
echo -e "${MAGENTA}╚══════════════════════════════════════════════════════╝${NC}"

# Quick internet check (non-fatal — attempt fallback DNS if ping fails)
if ! ping -c 1 -W 2 1.1.1.1 &>/dev/null; then
    warn "Không ping được 1.1.1.1 - thử kiểm tra kết nối DNS/HTTP..."
    if ! host archlinux.org &>/dev/null || ! curl -fsS --max-time 5 https://archlinux.org/ &>/dev/null; then
        error "Không có Internet. Kiểm tra kết nối mạng và thử lại."
    fi
fi

# require_cmd: fatal if not present

require_cmd(){
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        error "Thiếu lệnh cần thiết: $cmd - dừng script. Cài đặt package tương ứng trên ArchISO trước khi chạy."
    fi
}

# retry wrapper for commands (array-style)
retry_cmd(){
    local tries=4 delay=3 i=0 rc=0
    while (( i < tries )); do
        if "$@"; then
            return 0
        fi
        rc=$?
        i=$((i+1))
        warn "Lệnh thất bại (exit $rc). Thử lại (${i}/${tries}) sau ${delay}s..."
        sleep $delay
        delay=$((delay*2))
    done
    return $rc
}

# CRITICAL tools - check but don’t abort immediately; show helpful error
CRITICAL_CMDS=(sgdisk partprobe mkfs.fat mkfs.ext4 mkswap genfstab pacstrap arch-chroot lsblk wipefs blkid sed grep awk uname curl host)
for c in "${CRITICAL_CMDS[@]}"; do
    if ! command -v "$c" &>/dev/null; then
        warn "Cảnh báo: lệnh '$c' không có sẵn trong môi trường hiện tại."
    fi
done

# pacman-key init/populate if needed (avoid signature issues)
if ! pgrep -x "gpg-agent" &>/dev/null && command -v pacman-key &>/dev/null; then
    info "Đảm bảo pacman keyring đã được khởi tạo..."
    if [ ! -d /etc/pacman.d/gnupg ] || [ -z "$(ls -A /etc/pacman.d/gnupg 2>/dev/null || true)" ]; then
        pacman-key --init || true
        pacman-key --populate archlinux || true
    fi
fi

# Fix pacman.conf: safely ensure repo sections exist and multilib uncommented
info "Kiểm tra & sửa /etc/pacman.conf..."
if [[ -f /etc/pacman.conf ]]; then
    # Try to uncomment common multilib and mirrorlist lines (best-effort)
    sed -i '/^\s*#\s*\[multilib\]/,/^$/s/^\s*#\s*//' /etc/pacman.conf || true
    sed -i '/^\s*#\s*Include = \/etc\/pacman.d\/mirrorlist/s/^\s*#\s*//' /etc/pacman.conf || true
fi

# ensure /var/lib/pacman/sync exists
if [[ ! -d /var/lib/pacman/sync ]]; then
    info "Khởi tạo pacman database..."
    mkdir -p /var/lib/pacman/sync || true
fi

# Install reflector if possible (robust)
if ! command -v reflector &>/dev/null; then
    info "Cố gắng cài reflector tạm thời..."
    retry_cmd pacman -Sy --noconfirm reflector || warn "Không thể cài reflector - bỏ qua."
fi

# Use reflector to update mirrorlist (if available)
if command -v reflector &>/dev/null; then
    info "Chọn mirror (Vietnam ưu tiên nếu có)..."
    reflector --country Vietnam --latest 5 --sort rate --save /etc/pacman.d/mirrorlist --verbose || warn "reflector thất bại."
else
    info "Sử dụng mirrorlist fallback nếu cần..."
    if [[ ! -s /etc/pacman.d/mirrorlist ]]; then
        mkdir -p /etc/pacman.d
        echo "Server = https://mirrors.huongnguyen.dev/arch/\$repo/os/\$arch" > /etc/pacman.d/mirrorlist || true
    fi
fi

# Ensure main repos exist in pacman.conf - safer check & append only if absent
if ! grep -Eq '^\[core\]' /etc/pacman.conf; then
    warn "Không tìm thấy [core] trong /etc/pacman.conf - thêm mặc định."
    cat >> /etc/pacman.conf <<'REPOS'

[core]
Include = /etc/pacman.d/mirrorlist
REPOS
fi
if ! grep -Eq '^\[extra\]' /etc/pacman.conf; then
    cat >> /etc/pacman.conf <<'REPOS'

[extra]
Include = /etc/pacman.d/mirrorlist
REPOS
fi
if ! grep -Eq '^\[multilib\]' /etc/pacman.conf; then
    cat >> /etc/pacman.conf <<'REPOS'

[multilib]
Include = /etc/pacman.d/mirrorlist
REPOS
fi

# read_default helper
read_default(){
    local prompt="$1" default="$2" var
    read -rp "$prompt" var
    echo "${var:-$default}"
}

# Language & timezone menu
echo -e "\n${YELLOW}Ngôn ngữ: 1) English  2) Tiếng Việt  3) 日本語${NC}"
read -rp " → (mặc định 2): " lang_choice; lang_choice=${lang_choice:-2}
case $lang_choice in
    3) LANG_CODE="ja_JP.UTF-8"; KEYMAP="jp106" ;;
    1) LANG_CODE="en_US.UTF-8"; KEYMAP="us" ;;
    *) LANG_CODE="vi_VN.UTF-8"; KEYMAP="us" ;;
esac

echo -e "\n${YELLOW}Múi giờ: 1) Việt Nam  2) Hàn Quốc  3) Anh${NC}"
read -rp " → (mặc định 1): " tz_choice; tz_choice=${tz_choice:-1}
case $tz_choice in
    2) TIMEZONE="Asia/Seoul";;
    3) TIMEZONE="Europe/London";;
    *) TIMEZONE="Asia/Ho_Chi_Minh";;
esac

# Validate timezone exists
if [[ ! -f "/usr/share/zoneinfo/$TIMEZONE" ]]; then
    warn "Timezone $TIMEZONE không tồn tại, dùng UTC"
    TIMEZONE="UTC"
fi

# Username & hostname validation
while :; do
    read -rp "${BLUE}Username (a-z 0-9 _ -, mặc định: user): ${NC}" INPUT_USER
    USERNAME=${INPUT_USER:-user}
    if [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then break; else warn "Username chỉ được a-z, 0-9, _, - và không bắt đầu bằng số!"; fi
done

while :; do
    read -rp "${BLUE}Hostname (mặc định: tyno): ${NC}" INPUT_HOST
    HOSTNAME=${INPUT_HOST:-tyno}
    if [[ "$HOSTNAME" =~ ^[a-zA-Z0-9]{0,62}$ ]]; then break; else warn "Hostname không hợp lệ!"; fi
done

read -rsp "${BLUE}Password cho $USERNAME (mặc định = username): ${NC}" USER_PASS; echo
USER_PASS=${USER_PASS:-$USERNAME}
read -rsp "${BLUE}Password root (mặc định: root): ${NC}" ROOT_PASS; echo
ROOT_PASS=${ROOT_PASS:-root}

# Show physical disks
echo -e "\n${YELLOW}Danh sách ổ vật lý hiện có:${NC}"
lsblk -dpo NAME,SIZE,MODEL || true

# Disk selection - stricter detection
while :; do
    echo -e "\n${YELLOW}Ổ đĩa cài đặt (ví dụ: /dev/sda hoặc /dev/nvme0n1) - KHÔNG nhập partition như /dev/sda1:${NC}"
    read -r DISK
    DISK="${DISK%% }"; DISK="${DISK## }"
    if [[ -z "$DISK" ]]; then warn "Không được để trống!"; continue; fi
    if [[ ! "$DISK" =~ ^/dev/ ]]; then warn "Đường dẫn ổ không hợp lệ!"; continue; fi
    if [[ ! -b "$DISK" ]]; then warn "Ổ $DISK không tồn tại!"; continue; fi
    # ensure it’s a disk (not partition) via lsblk TYPE
    type=$(lsblk -dn -o TYPE "$DISK" 2>/dev/null || true)
    if [[ "$type" != "disk" ]]; then
        warn "Bạn đã nhập partition hoặc device không phải disk. Vui lòng nhập TÊN Ổ (ví dụ /dev/sda hoặc /dev/nvme0n1)."
        continue
    fi
    break
done

# FIX #10: Check disk space (minimum 20GB)
DISK_SIZE=$(lsblk -bdn -o SIZE "$DISK")
REQUIRED_SIZE=$((20 * 1024 * 1024 * 1024))  # 20GB
if (( DISK_SIZE < REQUIRED_SIZE )); then
    error "Disk quá nhỏ. Cần ít nhất 20GB, hiện có $(( DISK_SIZE / 1024 / 1024 / 1024 ))GB"
fi
info "Disk size: $(( DISK_SIZE / 1024 / 1024 / 1024 ))GB (OK)"

info "Unmount & cleanup partitions liên quan tới $DISK trước khi thao tác..."
umount -R /mnt 2>/dev/null || true
swapoff -a 2>/dev/null || true

mapfile -t parts < <(lsblk -lnpo NAME "$DISK" | tail -n +2 || true)
for p in "${parts[@]:-}"; do
    umount "$p" 2>/dev/null || true
done
sleep 1

if mount | grep -q "^${DISK}"; then
    warn "Vẫn có mount trên thiết bị $DISK. Hãy kiểm tra thủ công."
    mount | grep "$DISK" || true
    read -rp "Muốn tiếp tục và ép xoá tất cả partition trên $DISK? Gõ EXACT: FORMAT $DISK : " confirm_force
    [[ "$confirm_force" == "FORMAT $DISK" ]] || error "Hủy cài đặt."
fi

warn "TẤT CẢ DỮ LIỆU TRÊN $DISK SẼ BỊ XÓA!"
read -rp "Gõ YES để đồng ý: " c; [[ "$c" = "YES" ]] || error "Hủy."

# detect boot mode
if [ -d /sys/firmware/efi/efivars ]; then
    BOOT_MODE=uefi
    info "Phát hiện hệ thống boot: UEFI"
else
    BOOT_MODE=bios
    warn "Không tìm thấy EFI vars - hệ đang ở chế độ BIOS/Legacy. Sẽ tạo BIOS boot partition."
fi

# clean disk
# clean disk
wipefs -af "$DISK" 2>/dev/null || warn "wipefs gặp lỗi nhưng tiếp tục..."
sgdisk -Z "$DISK" 2>/dev/null || true

# Partition layout (preserve behavior)
if [[ "$BOOT_MODE" == "uefi" ]]; then
    sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI"   "$DISK"
    sgdisk -n 2:0:+8G   -t 2:8200 -c 2:"Swap"  "$DISK"
    sgdisk -n 3:0:0     -t 3:8300 -c 3:"Root"  "$DISK"
else
    sgdisk -n 1:0:+2M -t 1:EF02 -c 1:"BIOSBOOT" "$DISK"
    sgdisk -n 2:0:+8G   -t 2:8200 -c 2:"Swap"  "$DISK"
    sgdisk -n 3:0:0     -t 3:8300 -c 3:"Root"  "$DISK"
fi

# FIX: Better partition suffix detection (handles nvme, mmcblk, loop)
get_partition_suffix() {
    local disk="$1"
    if [[ "$disk" =~ (nvme|mmcblk|loop) ]]; then
        echo "p"
    else
        echo ""
    fi
}

p=$(get_partition_suffix "$DISK")

if [[ "$BOOT_MODE" == "uefi" ]]; then
    EFI="${DISK}${p}1"
    SWAP="${DISK}${p}2"
    ROOT="${DISK}${p}3"
else
    BIOSBOOT="${DISK}${p}1"
    SWAP="${DISK}${p}2"
    ROOT="${DISK}${p}3"
fi

sleep 1
partprobe "$DISK" || true

# FIX #2 & #6: Wait for partitions to appear with retry loop
info "Chờ kernel nhận diện partitions..."
for partition in "${ROOT}" "${SWAP}" "${EFI:-}" "${BIOSBOOT:-}"; do
    if [[ -z "$partition" ]]; then continue; fi

    for i in {1..20}; do
        if [[ -b "$partition" ]]; then
            info "✓ Partition $partition đã sẵn sàng"
            break
        fi
        if (( i == 20 )); then
            error "Timeout: Partition $partition không xuất hiện sau 10s. Kiểm tra sgdisk output."
        fi
        sleep 0.5
    done
done

info "Format partition(s), swap, root..."
umount -R /mnt 2>/dev/null || true
swapoff -a 2>/dev/null || true
for pt in "${EFI:-}" "${BIOSBOOT:-}" "${SWAP:-}" "${ROOT:-}"; do
    [[ -n "$pt" ]] && umount "$pt" 2>/dev/null || true
done

if [[ "$BOOT_MODE" == "uefi" ]]; then
    mkfs.fat -F32 "$EFI" || error "Format EFI partition thất bại"
fi

mkswap "$SWAP" || error "mkswap thất bại"
swapon "$SWAP" || error "swapon thất bại"
mkfs.ext4 -F "$ROOT" || error "Format root partition thất bại"

# mount
mount "$ROOT" /mnt || error "Mount root thất bại"
mkdir -p /mnt/etc

if [[ "$BOOT_MODE" == "uefi" ]]; then
    mount --mkdir "$EFI" /mnt/boot || error "Mount EFI thất bại"
else
    mkdir -p /mnt/boot
fi

# FIX #3: Generate fstab and validate content
info "Tạo fstab..."
genfstab -U /mnt > /mnt/etc/fstab || error "genfstab thất bại"

# Verify fstab has actual entries
if ! grep -q "^UUID=" /mnt/etc/fstab && ! grep -q "^/dev/" /mnt/etc/fstab; then
    error "fstab rỗng hoặc không chứa mount entries. Hệ thống sẽ không boot được!"
fi

# Verify root partition is in fstab
if ! grep -q "/[[:space:]]*ext4" /mnt/etc/fstab; then
    warn "Không tìm thấy root partition trong fstab. Nội dung fstab:"
    cat /mnt/etc/fstab
    error "fstab thiếu root mount - dừng để tránh lỗi boot."
fi

info "✓ fstab hợp lệ"

# Pacstrap with retry
info "Pacstrap base system..."
PACKAGES=(base base-devel linux linux-firmware linux-headers git vim sudo networkmanager polkit seatd intel-ucode amd-ucode efibootmgr dosfstools grub)
retry_cmd pacstrap -K /mnt "${PACKAGES[@]}" || error "pacstrap thất bại sau nhiều lần thử. Kiểm tra mạng và gói."

# Prepare chroot script (improved, preserves original features)
cat > /mnt/install.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

export USERNAME HOSTNAME USER_PASS ROOT_PASS TIMEZONE LANG_CODE KEYMAP DISK BOOT_MODE ROOT

warn(){ echo -e "[!] $*"; }
info(){ echo -e "[+] $*"; }
error(){ echo -e "[✗] $*"; exit 1; }

# ensure multilib enabled (best-effort)
if grep -q '^\s*#\s*\[multilib\]' /etc/pacman.conf; then
    sed -i '/^\s*#\s*\[multilib\]/,/^$/s/^\s*#\s*//' /etc/pacman.conf || true
    pacman -Syu --noconfirm || true
fi

# timezone/locale
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime || error "Timezone link thất bại"
hwclock --systohc || true

sed -i "s/^#\s*\($LANG_CODE.*\)/\1/" /etc/locale.gen || true
locale-gen || error "locale-gen thất bại"
echo "LANG=$LANG_CODE" > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

# hosts & hostname
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOS

# groups
for g in wheel audio video seat; do
    if ! getent group "$g" >/dev/null 2>&1; then
        groupadd -r "$g" || true
    fi
done

# create user
if ! id -u "$USERNAME" >/dev/null 2>&1; then
    useradd -m -G wheel,audio,video,seat "$USERNAME" || error "useradd thất bại"
fi
echo "$USERNAME:$USER_PASS" | chpasswd || error "Set user password thất bại"
echo "root:$ROOT_PASS" | chpasswd || error "Set root password thất bại"
echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/00-install
chmod 440 /etc/sudoers.d/00-install || true

IS_VM=$(systemd-detect-virt 2>/dev/null || echo none)
IS_VM=${IS_VM:-none}

# GPU detection
if [[ $IS_VM != "none" ]] && [[ $IS_VM != "oracle" ]]; then
    warn "VM không được hỗ trợ chính thức. Phát hiện: $IS_VM."
fi

HAS_NVIDIA=0
if [[ $IS_VM == "none" ]] && lspci | grep -iq 'VGA.*NVIDIA'; then
    HAS_NVIDIA=1
    info "Phát hiện NVIDIA GPU - cài driver..."
    pacman -S --noconfirm --needed nvidia nvidia-utils lib32-nvidia-utils nvidia-settings || true

    # Prevent duplicate nvidia modules in mkinitcpio.conf
    if ! grep -q "nvidia" /etc/mkinitcpio.conf; then
        info "Thêm NVIDIA modules vào mkinitcpio.conf"
        if grep -q '^MODULES=' /etc/mkinitcpio.conf; then
            sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
        else
            echo 'MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)' >> /etc/mkinitcpio.conf
        fi
    else
        info "NVIDIA modules đã có trong mkinitcpio.conf - bỏ qua"
    fi
else
    info "Cài Mesa drivers..."
    pacman -S --noconfirm --needed mesa lib32-mesa vulkan-icd-loader lib32-vulkan-icd-loader || true
fi

# core packages
info "Cài đặt Hyprland và packages chính..."
pacman -Syu --noconfirm --needed hyprland kitty wofi pipewire wireplumber pipewire-pulse xdg-desktop-portal-hyprland zsh sddm archlinux-wallpaper python-pip || true

systemctl enable NetworkManager sddm seatd pipewire wireplumber || true

# Bootloader installation with verification
BOOTLOADER_OK=0

if [[ "$BOOT_MODE" == "uefi" ]]; then
    info "Cài đặt systemd-boot..."
    pacman -S --noconfirm --needed efibootmgr dosfstools || true

    if bootctl --path=/boot install; then
        ROOT_UUID=$(blkid -s UUID -o value "$ROOT" 2>/dev/null || true)
        mkdir -p /boot/loader/entries

        if [[ -n "$ROOT_UUID" ]]; then
            cat > /boot/loader/entries/arch.conf <<LOADER
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=UUID=${ROOT_UUID} rw
LOADER
        else
            cat > /boot/loader/entries/arch.conf <<LOADER
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=${ROOT} rw
LOADER
        fi

        # Verify boot entry exists
        if [[ -f /boot/loader/entries/arch.conf ]]; then
            info "✓ systemd-boot đã cài thành công"
            BOOTLOADER_OK=1
        fi
    else
        warn "bootctl thất bại - thử GRUB EFI fallback"
    fi

    # Fallback to GRUB if systemd-boot failed
    if [[ $BOOTLOADER_OK -eq 0 ]]; then
        info "Cài GRUB cho UEFI..."
        pacman -S --noconfirm --needed grub efibootmgr dosfstools || true
        mkdir -p /boot/EFI/BOOT || true

        if grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB; then
            cp /boot/EFI/GRUB/grubx64.efi /boot/EFI/BOOT/BOOTX64.EFI 2>/dev/null || true
            if grub-mkconfig -o /boot/grub/grub.cfg; then
                info "✓ GRUB EFI đã cài thành công"
                BOOTLOADER_OK=1
            fi
        fi
    fi
else
    # BIOS mode
    info "Cài GRUB cho BIOS..."
    pacman -S --noconfirm --needed grub || true
    if grub-install --target=i386-pc "$DISK"; then
        if grub-mkconfig -o /boot/grub/grub.cfg; then
            info "✓ GRUB BIOS đã cài thành công"
            BOOTLOADER_OK=1
        fi
    fi
fi

# Fatal error if no bootloader installed
if [[ $BOOTLOADER_OK -eq 0 ]]; then
    error "BOOTLOADER INSTALLATION FAILED! Hệ thống sẽ KHÔNG boot được. Kiểm tra log và thử lại."
fi

# Verify bootloader entry in EFI (UEFI only)
if [[ "$BOOT_MODE" == "uefi" ]]; then
    if efibootmgr 2>/dev/null | grep -qi "arch\|grub\|boot"; then
        info "✓ Boot entry đã được tạo trong EFI"
    else
        warn "⚠ Không tìm thấy boot entry trong efibootmgr. Có thể cần boot thủ công lần đầu."
    fi
fi

# Create user AUR environment: build yay
su - "$USERNAME" -s /bin/bash <<'ENDUSER'
set -e
export PATH="$HOME/.local/bin:$PATH"

if ! command -v yay &>/dev/null; then
    echo "[+] Building yay from AUR..."
    git clone https://aur.archlinux.org/yay.git /tmp/yay && cd /tmp/yay || exit 0
    if [[ -f PKGBUILD ]]; then
        if makepkg -si --noconfirm; then
            echo "[+] yay installed successfully"
        else
            echo "[!] yay build failed - skipping AUR packages"
            cd / && rm -rf /tmp/yay || true
            exit 0
        fi
    fi
    cd / && rm -rf /tmp/yay || true
fi

# install AUR packages (best-effort)
if command -v yay &>/dev/null; then
    yay -S --noconfirm --needed wal-colors ttf-jetbrains-mono-nerd catppuccin-sddm-mocha hyprland-nvidia || true
fi

# clone config repo if available
if git clone --depth 1 https://github.com/mkhmtolzhas/Invincible-Dots.git /tmp/Invincible-Dots 2>/dev/null; then
    cp -r /tmp/Invincible-Dots/.config/* ~/.config/ 2>/dev/null || true
    find ~/.config -type f -exec sed -i "s|mkhmtcore|$USERNAME|g" {} + 2>/dev/null || true
    rm -rf /tmp/Invincible-Dots || true
fi

# apply wal if available (best-effort)
wal -i /usr/share/backgrounds/archlinux/archwave.png 2>/dev/null || true
ENDUSER

# sddm theme config
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/kde_settings.conf <<SDDM
[Theme]
Current=catppuccin-mocha

[General]
DisplayServer=wayland
SDDM

# hyprland session file
mkdir -p /usr/share/wayland-sessions
cat > /usr/share/wayland-sessions/hyprland.desktop <<DESKTOP
[Desktop Entry]
Name=Hyprland
Comment=A dynamic tiling Wayland compositor
Exec=Hyprland
Type=Application
DESKTOP

# VM & NVIDIA env shims
if [[ $IS_VM == "oracle" ]]; then
    echo 'export WLR_NO_HARDWARE_CURSORS=1' >> /home/$USERNAME/.zshrc || true
fi
if [[ $HAS_NVIDIA -eq 1 ]]; then
    cat >> /home/$USERNAME/.zshrc <<NV
export GBM_BACKEND=nvidia-drm
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export LIBVA_DRIVER_NAME=nvidia
export WLR_RENDERER=vulkan
NV
fi
chown $USERNAME:$USERNAME /home/$USERNAME/.zshrc || true

chsh -s /usr/bin/zsh "$USERNAME" || true

info "Rebuild initramfs với modules mới..."
mkinitcpio -P || warn "mkinitcpio có warning nhưng tiếp tục..."

info "✓ Cài đặt trong chroot hoàn tất"
EOF

chmod +x /mnt/install.sh

# Run chroot script with environment
info "Chạy script cài đặt trong chroot environment..."
if ! arch-chroot /mnt env USERNAME="$USERNAME" HOSTNAME="$HOSTNAME" USER_PASS="$USER_PASS" ROOT_PASS="$ROOT_PASS" TIMEZONE="$TIMEZONE" LANG_CODE="$LANG_CODE" KEYMAP="$KEYMAP" DISK="$DISK" BOOT_MODE="$BOOT_MODE" ROOT="$ROOT" /install.sh; then
    error "Chroot script thất bại! Kiểm tra log tại $LOG. Hệ thống có thể chưa được cài đầy đủ."
fi

# cleanup
rm -f /mnt/install.sh || true
umount -R /mnt 2>/dev/null || true
swapoff -a 2>/dev/null || true

echo ""
echo -e "${MAGENTA}╔════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║       CÀI ĐẶT HOÀN TẤT - FIXED SCRIPT V3       ║${NC}"
echo -e "${MAGENTA}╠════════════════════════════════════════════════╣${NC}"
echo -e "${MAGENTA}║   User     : ${GREEN}$USERNAME${MAGENTA}       ║${NC}"
echo -e "${MAGENTA}║   Hostname : ${GREEN}$HOSTNAME${MAGENTA}       ║${NC}"
echo -e "${MAGENTA}║   Boot Mode: ${GREEN}$BOOT_MODE${MAGENTA}      ║${NC}"
echo -e "${MAGENTA}║   Root Dev : ${GREEN}$ROOT${MAGENTA}           ║${NC}"
echo -e "${MAGENTA}╠════════════════════════════════════════════════╣${NC}"
echo -e "${MAGENTA}║  ${YELLOW}Khởi động lại máy: reboot${MAGENTA}       ║${NC}"
echo -e "${MAGENTA}║  ${YELLOW}Log file: $LOG${MAGENTA}             ║${NC}"
echo -e "${MAGENTA}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✓ Script by TYNO - FIXED V3 2025${NC}"
read -rp "Nhấn Enter để kết thúc hoặc gõ 'reboot' để khởi động lại: " final_action
if [[ "$final_action" == "reboot" ]]; then
    reboot
fi
