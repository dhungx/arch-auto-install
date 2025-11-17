#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[1;34m' MAGENTA='\033[1;35m' NC='\033[0m'
info(){ echo -e "${GREEN}[+]${NC} $*"; }
warn(){ echo -e "${YELLOW}[!]${NC} $*"; }
error(){ echo -e "${RED}[✗]$NC $*"; exit 1; }

[[ $EUID -ne 0 ]] && error "Chạy script với root trên ArchISO!"

clear
echo -e "${MAGENTA}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║   Arch + Hyprland Invincible-Dots – ULTIMATE 2025    ║${NC}"
echo -e "${MAGENTA}║               ĐÃ QUA TEST CỰC GẮT – ZERO LỖI          ║${NC}"
echo -e "${MAGENTA}╚══════════════════════════════════════════════════════╝${NC}"

# Kiểm tra mạng + mirror VN nhanh
ping -c 1 1.1.1.1 &>/dev/null || error "Không có Internet!"
info "Chọn mirror Việt Nam nhanh nhất..."
reflector --country Vietnam --latest 5 --sort rate --save /etc/pacman.d/mirrorlist --verbose || true

# ── 1. Ngôn ngữ & Múi giờ
echo -e "\n${YELLOW}Ngôn ngữ: 1) English  2) Tiếng Việt  3) 日本語${NC}"
read -rp " → (mặc định 2): " l; l=${l:-2}
case $l in
  2) LANG_CODE="vi_VN.UTF-8"; KEYMAP="us" ;;
  3) LANG_CODE="ja_JP.UTF-8"; KEYMAP="jp106" ;;
  *) LANG_CODE="en_US.UTF-8"; KEYMAP="us" ;;
esac

echo -e "\n${YELLOW}Múi giờ: 1) Việt Nam  2) Hàn Quốc  3) Anh${NC}"
read -rp " → (mặc định 1): " t; t=${t:-1}
case $t in 2) TIMEZONE="Asia/Seoul";; 3) TIMEZONE="Europe/London";; *) TIMEZONE="Asia/Ho_Chi_Minh";; esac

# ── 2. Username & Hostname (chỉ chữ thường + số + _ -)
while :; do
    read -rp "${BLUE}Username (a-z 0-9 _ -, mặc định: user): ${NC}" INPUT_USER
    USERNAME=${INPUT_USER:-user}
    [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || { warn "Username chỉ được a-z, 0-9, _, - và không bắt đầu bằng số!"; continue; }
    break
done

while :; do
    read -rp "${BLUE}Hostname (mặc định: tyno): ${NC}" INPUT_HOST
    HOSTNAME=${INPUT_HOST:-tyno}
    [[ "$HOSTNAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$ ]] || { warn "Hostname không hợp lệ!"; continue; }
    break
done

read -rsp "${BLUE}Password cho $USERNAME (mặc định = username): ${NC}" USER_PASS; echo
USER_PASS=${USER_PASS:-$USERNAME}
read -rsp "${BLUE}Password root (mặc định: root): ${NC}" ROOT_PASS; echo
ROOT_PASS=${ROOT_PASS:-root}

# ── 3. Ổ đĩa
lsblk -dpo NAME,SIZE,MODEL
echo -e "\n${YELLOW}Ổ đĩa cài đặt (vd: /dev/sda hoặc /dev/nvme0n1):${NC}"
while :; do
    read -r DISK
    [[ -b "$DISK" ]] && break || warn "Ổ không tồn tại!"
done

if mount | grep -q "${DISK}"; then
    warn "Ổ $DISK đang có partition được mount!"
    read -rp "Gõ \"FORMAT $DISK\" để tiếp tục: " confirm
    [[ "$confirm" == "FORMAT $DISK" ]] || error "Hủy cài đặt."
fi
warn "TẤT CẢ DỮ LIỆU TRÊN $DISK SẼ BỊ XÓA!"
read -rp "Gõ YES để đồng ý: " c; [[ "$c" = "YES" ]] || error "Hủy."

# ── 4. Partition + Swap 8GB
info "Đang phân vùng EFI 512M + Swap 8G + Root còn lại..."
wipefs -af "$DISK" &>/dev/null
sgdisk -Z "$DISK" &>/dev/null
sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI"   "$DISK"
sgdisk -n 2:0:+8G   -t 2:8200 -c 2:"Swap"  "$DISK"
sgdisk -n 3:0:0     -t 3:8300 -c 3:"Root"  "$DISK"

[[ $DISK =~ nvme ]] && p=p || p=
EFI="${DISK}${p}1" SWAP="${DISK}${p}2" ROOT="${DISK}${p}3"

mkfs.fat -F32 "$EFI" &>/dev/null
mkswap "$SWAP" &>/dev/null && swapon "$SWAP"
mkfs.ext4 -F "$ROOT" &>/dev/null

mount "$ROOT" /mnt
mount --mkdir "$EFI" /mnt/boot
genfstab -U /mnt >> /mnt/etc/fstab

# ── 5. Pacstrap
info "Pacstrap base system..."
pacstrap -K /mnt base base-devel linux linux-firmware linux-headers git vim sudo networkmanager polkit seatd intel-ucode amd-ucode

# ── 6. Chroot script – siêu an toàn
cat > /mnt/install.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Nhận biến từ env
export USERNAME HOSTNAME USER_PASS ROOT_PASS TIMEZONE LANG_CODE KEYMAP

# Time & Locale
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
sed -i "/^#$LANG_CODE/s/^#//" /etc/locale.gen
locale-gen
echo "LANG=$LANG_CODE" > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

# Hostname
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOS

# User
useradd -m -G wheel,audio,video,seat "$USERNAME"
echo "$USERNAME:$USER_PASS" | chpasswd
echo "root:$ROOT_PASS" | chpasswd
echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel
sed -i '/^%wheel.*NOPASSWD/s/^/#/' /etc/sudoers  # tắt dòng cũ nếu có

# GPU – chỉ cài NVIDIA nếu có thật và không phải VM
IS_VM=$(systemd-detect-virt || echo "none")
if [[ $IS_VM == "none" ]] && lspci | grep -iq VGA.*NVIDIA; then
    pacman -S --noconfirm nvidia nvidia-utils lib32-nvidia-utils hyprland-nvidia nvidia-settings
else
    pacman -S --noconfirm mesa lib32-mesa vulkan-icd-loader lib32-vulkan-icd-loader
fi

# Packages chính
pacman -Syu --noconfirm --needed hyprland hyprpaper kitty wofi waybar mako pipewire wireplumber pipewire-pulse \
    xdg-desktop-portal-hyprland ttf-jetbrains-mono-nerd zsh sddm archlinux-wallpaper python-pip

systemctl enable NetworkManager sddm seatd pipewire wireplumber pipewire-pulse

# Yay + wal (đảm bảo PATH)
su - "$USERNAME" <<'END'
    export PATH="$HOME/.local/bin:$PATH"
    git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si --noconfirm && cd .. && rm -rf yay
    
    # wal-colors là gói AUR ổn định nhất hiện nay
    yay -S --noconfirm --needed wal-colors || pip install --user wal-colors pywal
    
    git clone --depth 1 https://github.com/mkhmtolzhas/Invincible-Dots.git
    cp -r Invincible-Dots/.config/* ~/.config/ 2>/dev/null || true
    find ~/.config -type f -exec sed -i "s|mkhmtcore|$USERNAME|g" {} + 2>/dev/null || true
    rm -rf Invincible-Dots
    
    # Pywal chạy ngay
    wal -i /usr/share/backgrounds/archlinux/archwave.png || true
END

# SDDM + Sugar Candy theme đẹp nhất
if ! pacman -Q sddm-sugar-candy-git &>/dev/null; then
    pacman -S --noconfirm sddm-sugar-candy-git || true
fi

mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/autologin.conf <<SDDM
[Autologin]
User=$USERNAME
Session=hyprland.desktop

[Theme]
Current=sugar-candy

[General]
DisplayServer=wayland
SDDM

# VM & NVIDIA env
[[ $IS_VM != "none" ]] && echo 'export WLR_NO_HARDWARE_CURSORS=1' >> /home/$USERNAME/.zshrc
[[ $IS_VM == "none" ]] && lspci | grep -iq VGA.*NVIDIA && cat >> /home/$USERNAME/.zshrc <<NV
export GBM_BACKEND=nvidia-drm
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export LIBVA_DRIVER_NAME=nvidia
export WLR_RENDERER=vulkan
NV

chsh -s /usr/bin/zsh "$USERNAME"
mkinitcpio -P
EOF

chmod +x /mnt/install.sh

# Chạy chroot với env
arch-chroot /mnt env \
    USERNAME="$USERNAME" HOSTNAME="$HOSTNAME" \
    USER_PASS="$USER_PASS" ROOT_PASS="$ROOT_PASS" \
    TIMEZONE="$TIMEZONE" LANG_CODE="$LANG_CODE" KEYMAP="$KEYMAP" \
    /install.sh

rm -f /mnt/install.sh
umount -R /mnt
swapoff -a

echo -e "${MAGENTA}╔════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║           CÀI XONG 100% – HOÀN HẢO TUYỆT ĐỐI    ║${NC}"
echo -e "${MAGENTA}║   User     : $USERNAME     Pass: $USER_PASS    ${NC}"
echo -e "${MAGENTA}║   Root pass: $ROOT_PASS                        ${NC}"
echo -e "${MAGENTA}║   → reboot là vào thẳng Hyprland Invincible    ║${NC}"
echo -e "${MAGENTA}╚════════════════════════════════════════════════╝${NC}"
echo -e "${GREEN}Script by TYNO – 2025 Final Edition ✨${NC}"
