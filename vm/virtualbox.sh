#!/usr/bin/env bash
set -euo pipefail

# Arch + Hyprland VM Fix Script (VirtualBox Only)
# Chạy script này sau khi cài xong auto.sh nếu застряva ở TTY

LOG=/tmp/vm-fix.log
rm -f "$LOG" || true; touch "$LOG"
exec > >(tee -a "$LOG") 2>&1

# Colors (use $'...' so variables contain real escape bytes)
RED=$'\e[0;31m'
GREEN=$'\e[0;32m'
YELLOW=$'\e[1;33m'
BLUE=$'\e[1;34m'
MAGENTA=$'\e[0;35m'
NC=$'\e[0m'

info(){ printf '%b\n' "${GREEN}[+]${NC} $*"; }
warn(){ printf '%b\n' "${YELLOW}[!]${NC} $*"; }
error(){ printf '%b\n' "${RED}[✗]${NC} $*"; exit 1; }

clear
echo -e "${MAGENTA}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║     Arch + Hyprland VM Fix Script (VirtualBox)     ║${NC}"
echo -e "${MAGENTA}║            Fix boot vào GUI cho VM                 ║${NC}"
echo -e "${MAGENTA}╚════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if running as root
[[ $EUID -ne 0 ]] && error "Phải chạy script với sudo! (ví dụ: sudo ./vm/virtualbox.sh)"

# Detect if running in VirtualBox
info "Kiểm tra môi trường VM..."
if command -v systemd-detect-virt &>/dev/null; then
    VM_TYPE=$(systemd-detect-virt 2>/dev/null || echo "none")
else
    VM_TYPE="unknown"
fi

if [[ "$VM_TYPE" != "oracle" ]] && ! lspci 2>/dev/null | grep -iq "VirtualBox\|VMware SVGA"; then
    read -rp "Bạn có chắc muốn tiếp tục? (yes/no): " confirm
    [[ "$confirm" != "yes" ]] && error "Hủy bỏ - script chỉ dùng cho VirtualBox"
fi

info "✓ Phát hiện VirtualBox VM"

# Check internet connection
info "Kiểm tra kết nối Internet..."
if ! ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
    error "Không có Internet! Kết nối mạng và thử lại."
fi
info "✓ Kết nối Internet OK"

echo ""
info "═══════════════════════════════════════════════════"
info "Bước 1: Cài VirtualBox Guest Additions + Drivers"
info "═══════════════════════════════════════════════════"

PACKAGES=(virtualbox-guest-utils)
FAILED_PACKAGES=()

for pkg in "${PACKAGES[@]}"; do
    if pacman -Q "$pkg" &>/dev/null; then
        info "✓ $pkg đã được cài đặt"
    else
        info "Đang cài $pkg..."
        if pacman -S --noconfirm --needed "$pkg" 2>&1 | tee -a "$LOG"; then
            info "✓ Cài $pkg thành công"
        else
            warn "✗ Không thể cài $pkg"
            FAILED_PACKAGES+=("$pkg")
        fi
    fi
done

if [[ ${#FAILED_PACKAGES[@]} -gt 0 ]]; then
    warn "Một số package không cài được: ${FAILED_PACKAGES[*]}"
    warn "Hệ thống có thể vẫn hoạt động nhưng không tối ưu"
fi

# Step 2: Enable VirtualBox services
echo ""
info "═══════════════════════════════════════════════════"
info "Bước 2: Enable VirtualBox Services"
info "═══════════════════════════════════════════════════"

if systemctl enable vboxservice 2>&1 | tee -a "$LOG"; then
    info "✓ vboxservice enabled"
    if systemctl start vboxservice 2>&1 | tee -a "$LOG"; then
        info "✓ vboxservice started"
    else
        warn "Không thể start vboxservice (có thể cần reboot)"
    fi
else
    warn "Không thể enable vboxservice"
fi

# Step 3: Set graphical.target as default
echo ""
info "═══════════════════════════════════════════════════"
info "Bước 3: Set Graphical Target làm mặc định"
info "═══════════════════════════════════════════════════"

CURRENT_TARGET=$(systemctl get-default 2>/dev/null || echo "unknown")
info "Target hiện tại: $CURRENT_TARGET"

if [[ "$CURRENT_TARGET" != "graphical.target" ]]; then
    if systemctl set-default graphical.target 2>&1 | tee -a "$LOG"; then
        info "✓ Đã set graphical.target làm mặc định"
    else
        error "Không thể set graphical.target"
    fi
else
    info "✓ graphical.target đã là mặc định"
fi

# Step 4: Configure SDDM for X11 (more stable in VM)
echo ""
info "═══════════════════════════════════════════════════"
info "Bước 4: Cấu hình SDDM dùng X11 (ổn định hơn Wayland)"
info "═══════════════════════════════════════════════════"

mkdir -p /etc/sddm.conf.d || true

SDDM_CONF="/etc/sddm.conf.d/kde_settings.conf"
if [[ -f "$SDDM_CONF" ]]; then
    info "Backup config cũ..."
    cp "$SDDM_CONF" "${SDDM_CONF}.backup-$(date +%s)" || true
fi

cat > "$SDDM_CONF" <<'SDDMCONF'
[Theme]
Current=catppuccin-mocha

[General]
DisplayServer=x11

[X11]
ServerArguments=-nolisten tcp
SDDMCONF

if [[ -f "$SDDM_CONF" ]]; then
    info "✓ SDDM config đã được cập nhật (dùng X11)"
else
    warn "Không thể tạo SDDM config"
fi

# Step 5: Add VM-specific environment variables
echo ""
info "═══════════════════════════════════════════════════"
info "Bước 5: Thêm Environment Variables cho VM"
info "═══════════════════════════════════════════════════"

ENV_FILE="/etc/environment"
VARS_TO_ADD=(
    "WLR_NO_HARDWARE_CURSORS=1"
    "WLR_RENDERER=pixman"
    "QT_QPA_PLATFORM=xcb"
)

for var in "${VARS_TO_ADD[@]}"; do
    if grep -q "^${var%%=*}=" "$ENV_FILE" 2>/dev/null; then
        info "✓ $var đã tồn tại trong $ENV_FILE"
    else
        echo "$var" >> "$ENV_FILE"
        info "✓ Đã thêm $var vào $ENV_FILE"
    fi
done

# Step 6: Verify and enable SDDM
echo ""
info "═══════════════════════════════════════════════════"
info "Bước 6: Kiểm tra và Enable SDDM"
info "═══════════════════════════════════════════════════"

if systemctl is-enabled sddm &>/dev/null; then
    info "✓ SDDM đã được enabled"
else
    if systemctl enable sddm 2>&1 | tee -a "$LOG"; then
        info "✓ Đã enable SDDM"
    else
        warn "Không thể enable SDDM"
    fi
fi

# Check SDDM status
if systemctl is-active sddm &>/dev/null; then
    info "✓ SDDM đang chạy"
else
    info "SDDM chưa chạy (sẽ start sau reboot)"
fi

# Step 7: Install Xorg (if not present) for X11 fallback
echo ""
info "═══════════════════════════════════════════════════"
info "Bước 7: Kiểm tra Xorg Server"
info "═══════════════════════════════════════════════════"

if ! pacman -Q xorg-server &>/dev/null; then
    info "Cài Xorg server..."
    if pacman -S --noconfirm --needed xorg-server xorg-xinit 2>&1 | tee -a "$LOG"; then
        info "✓ Xorg đã được cài đặt"
    else
        warn "Không thể cài Xorg - có thể cần cài thủ công"
    fi
else
    info "✓ Xorg đã được cài đặt"
fi

# Step 8: Create troubleshooting info
echo ""
info "═══════════════════════════════════════════════════"
info "Bước 8: Tạo thông tin troubleshooting"
info "═══════════════════════════════════════════════════"

TROUBLESHOOT_FILE="/root/vm-troubleshoot.txt"
cat > "$TROUBLESHOOT_FILE" <<'TROUBLE'
╔════════════════════════════════════════════════════╗
║        VirtualBox VM Troubleshooting Guide         ║
╚════════════════════════════════════════════════════╝

Nếu sau khi reboot vẫn kẹt ở TTY:

1. KIỂM TRA 3D ACCELERATION (QUAN TRỌNG!):
   - Tắt VM
   - Settings → Display → Enable "3D Acceleration"
   - Video Memory: 128MB
   - Graphics Controller: VMSVGA

2. THỬ KHỞI ĐỘNG HYPRLAND THỦ CÔNG:
   export WLR_NO_HARDWARE_CURSORS=1
   export WLR_RENDERER=pixman
   Hyprland

3. KIỂM TRA LOG:
   journalctl -u sddm -b
   journalctl -xe

4. THỬ START SDDM THỦ CÔNG:
   sudo systemctl start sddm

5. KIỂM TRA GRAPHICAL TARGET:
   systemctl get-default
   # Phải là: graphical.target

6. NẾU VẪN KHÔNG ĐƯỢC, THỬ PLASMA (STABLE HƠN):
   sudo pacman -S plasma-desktop
   # Chọn Plasma session trong SDDM

7. FALLBACK: DÙNG STARTX
   echo "exec Hyprland" > ~/.xinitrc
   startx

8. LIÊN HỆ HỖ TRỢ:
   - Log file: /tmp/vm-fix.log
   - Github Issues: [URL repo của bạn]

╔════════════════════════════════════════════════════╗
║              Thông tin hệ thống                    ║
╚════════════════════════════════════════════════════╝
TROUBLE

# Append system info
{
    echo ""
    echo "=== System Information ==="
    echo "Date: $(date)"
    echo "VM Type: $VM_TYPE"
    echo "Default Target: $(systemctl get-default 2>/dev/null || echo 'unknown')"
    echo "SDDM Status: $(systemctl is-enabled sddm 2>/dev/null || echo 'unknown')"
    echo ""
    echo "=== Installed Packages ==="
    pacman -Q | grep -E 'virtualbox|xorg|hyprland|sddm' || echo "No relevant packages"
    echo ""
    echo "=== Graphics Info ==="
    lspci | grep -i vga || echo "No VGA info"
    echo ""
} >> "$TROUBLESHOOT_FILE"

info "✓ Tạo troubleshooting guide tại: $TROUBLESHOOT_FILE"

# Final summary
echo ""
echo -e "${MAGENTA}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║              FIX HOÀN TẤT - VM READY               ║${NC}"
echo -e "${MAGENTA}╚════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✓ Các thay đổi đã được áp dụng:${NC}"
echo -e "  1. VirtualBox Guest Additions + Drivers"
echo -e "  2. Graphical target được set mặc định"
echo -e "  3. SDDM dùng X11 (stable hơn Wayland)"
echo -e "  4. Environment variables cho VM"
echo -e "  5. Xorg server cho fallback"
echo ""
echo -e "${YELLOW}⚠ QUAN TRỌNG - Trước khi reboot:${NC}"
echo -e "  → Tắt VM và vào Settings"
echo -e "  → Display → Enable '3D Acceleration' ✓"
echo -e "  → Video Memory: 128MB"
echo -e "  → Graphics Controller: VMSVGA"
echo ""
echo -e "${BLUE}📋 Log file: $LOG${NC}"
echo -e "${BLUE}📋 Troubleshoot guide: $TROUBLESHOOT_FILE${NC}"
echo ""

# Ask for reboot
read -rp "Bạn có muốn reboot ngay bây giờ? [yes/no]: " REBOOT_CHOICE

if [[ "$REBOOT_CHOICE" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo ""
    info "Đang reboot sau 3 giây..."
    sleep 1 && echo "3..." && sleep 1 && echo "2..." && sleep 1 && echo "1..."
    systemctl reboot
else
    echo ""
    warn "Nhớ reboot thủ công để áp dụng thay đổi: sudo reboot"
    echo -e "${GREEN}Và ĐỪNG QUÊN enable 3D Acceleration trong VirtualBox Settings!${NC}"
fi
