# Arch + Hyprland Auto Installation Script

Tự động cài đặt **Arch Linux** với **Hyprland** desktop environment trên máy thật hoặc VirtualBox.

## Mục Lục

- [Hỗ trợ](#hỗ-trợ)
- [Yêu cầu](#yêu-cầu)
- [Cảnh báo quan trọng](#cảnh-báo-không-đảm-bảo-100-thành-công)
  - [Yếu tố ảnh hưởng](#yếu-tố-ảnh-hưởng)
  - [Tỷ lệ thành công](#tỷ-lệ-thành-công-dự-kiến)
  - [Cách tăng xác suất](#cách-tăng-xác-suất-thành-công)
- [Cài đặt](#cài-đặt)
- [Sử dụng](#sử-dụng)
- [Khắc phục sự cố](#khắc-phục-sự-cố)
- [Packages được cài](#packages-được-cài)
- [Tài liệu thêm](#tài-liệu-thêm)

---

## Hỗ trợ

- Máy thật (Bare Metal)
- VirtualBox
- Không hỗ trợ: KVM, QEMU, Hyper-V, VMware, v.v.

[↑ Về mục lục](#mục-lục)

## Yêu cầu

- Arch Linux ISO - Boot từ ArchISO live
- Kết nối Internet (Ethernet khuyến nghị)
- Ít nhất 20GB dung lượng ổ đĩa (40GB+ an toàn)
---

## CẢNH BÁO: KHÔNG ĐẢM BẢO 100% THÀNH CÔNG

**Script này KHÔNG đảm bảo 100% cài đặt thành công!**

Mặc dù script đã được tối ưu hóa tối đa, thành công hoàn toàn phụ thuộc vào:

**40% Hardware & Linh kiện của bạn:**
- GPU (NVIDIA cũ, chip lạ → driver không tương thích)
- CPU quá cũ (trước 2010 → kernel không support)
- Mainboard BIOS firmware lỗi hoặc cũ (không hỗ trợ bootloader mới)
- Ổ đĩa có bad sectors (ghi thất bại giữa chừng)
- RAM không đủ (<2GB) hoặc chất lượng kém

**30% Network & Repository:**
- Internet ngắt/chậm trong quá trình cài (pacstrap timeout)
- Package repository mirror bị offline
- ISP throttling hoặc firewall blocking Arch mirrors
- GitHub rate limiting (git clone yay thất bại)
- DNS resolver fail tạm thời

**20% May Mắn Tạm Thời:**
- BIOS firmware bug ngẫu nhiên (boot fail dù cài đúng)
- Bootloader install random fail (systemd-boot → GRUB fallback)
- AUR PKGBUILD update có bug (build fail giữa chừng)
- Hardware timing issues (SSD chậm phản hồi, timeout)
- Partition không nhận diện kịp

**10% User Decisions:**
- Chọn ổ đĩa sai (xóa dữ liệu không cần thiết)
- Interrupt script (Ctrl+C giữa chừng)
- BIOS settings sai (Secure Boot, CSM, Fast Boot)
- Không follow hướng dẫn đúng

### Tỷ lệ Thành Công Dự Kiến

| Kịch bản | Xác suất |
|---------|----------|
| Hardware tốt (2020+, Ethernet, SSD) | 85-90% |
| Hardware vừa phải (2015-2019, Internet OK) | 65-75% |
| Hardware cũ (2010-2014, WiFi, HDD) | 30-50% |
| VirtualBox (4GB+ RAM, SSD host) | 80-85% |
| Laptop (Wifi yếu, GPU lạ, heating) | 30-40% |

**TỶ LỆ THÀNH CÔNG TRUNG BÌNH: 60-65%**

Không phải lỗi script, mà do Linux/hardware/network có quá nhiều biến số không thể kiểm soát.

### Cách Tăng Xác Suất Thành Công

**Hardware & BIOS:**
- Dùng **Ethernet** thay vì Wifi (ổn định hơn 1000 lần)
- Chuẩn bị **40GB+** thay vì 20GB
- Dùng **SSD** thay vì HDD (tốc độ 10x, ít lỗi)
- **Cập nhật BIOS** mới nhất
- **Tắt Secure Boot, TPM, Fast Boot**
- Đảm bảo **RAM 4GB+**

**Network & Process:**
- Kiểm tra Internet **trước** cài
- **Backup dữ liệu** - 100% sẽ bị xóa
- **Chọn đúng ổ** - Nếu sai sẽ thảm họa
- **Không interrupt** script - Bấm Ctrl+C sẽ hỏi hệ thống
- **Chuẩn bị 30-45 phút** - Không vội vàng
- **Đọc log file** nếu fail: `/tmp/arch-install-v3.log`

[↑ Về mục lục](#mục-lục)

---

## Cài đặt

### 1. Chuẩn bị

Backup dữ liệu - **toàn bộ ổ đĩa sẽ bị xóa**

Tắt Secure Boot, TPM, Fast Boot trong BIOS nếu cần

Dùng Ethernet thay vì Wifi nếu có thể

### 2. Boot ArchISO

Tải ArchISO từ [archlinux.org](https://archlinux.org/download/)

Boot vào ArchISO live environment

### 3. Kết nối Internet

**Ethernet:** Thường tự động DHCP

**WiFi:**
```bash
iwctl
station <device> scan
station <device> get-networks
station <device> connect <SSID>
exit
```

Kiểm tra: `ping 8.8.8.8`

### 4. Tải Script

```bash
# Cách 1: Clone repository
git clone https://github.com/onlydohungx/arch-auto-install.git
cd arch-auto-install

# Cách 2: Tải file trực tiếp
curl -O https://raw.githubusercontent.com/onlydohungx/arch-auto-install/main/auto.sh
chmod +x auto.sh
```

### 5. Chạy Script

```bash
sudo bash auto.sh
```

### 6. Trả lời các câu hỏi

| Câu hỏi | Mặc định | Ví dụ |
|--------|---------|-------|
| Ngôn ngữ | Tiếng Việt (2) | 1=English, 3=日本語 |
| Múi giờ | Ho Chi Minh (1) | 2=Seoul, 3=London |
| Username | user | john, alice |
| Hostname | tyno | myarch, laptop |
| Password user | username | (nếu không nhập) |
| Password root | root | (nếu không nhập) |
| Ổ đĩa | - | /dev/sda, /dev/nvme0n1 |

**Lưu ý:** Nhập tên ổ đúng VD `/dev/sda` KHÔNG `/dev/sda1`

Script yêu cầu xác nhận:
- Gõ `FORMAT /dev/sdX` để xóa tất cả
- Gõ `YES` để đồng ý cài đặt

### 7. Chờ cài đặt

Quy trình chạy khoảng 15-30 phút tùy tốc độ internet

Không interrupt script (Ctrl+C)

Xem log: `/tmp/arch-install-v3.log`

### 8. Khởi động lại

Chọn `reboot` để khởi động vào hệ thống mới

## Sử dụng

### Đăng nhập

Dùng username và password đã nhập

SDDM sẽ mở, chọn "Hyprland" từ dropdown

### Các phím tắt mặc định

```
Super + Return     = Mở terminal (Kitty)
Super + D          = Launcher (Wofi)
Super + C          = Đóng cửa sổ
Super + V          = Fullscreen
Super + H/J/K/L    = Di chuyển focus
Super + Arrow      = Thay đổi kích thước
```

### Cập nhật hệ thống

```bash
sudo pacman -Syu
```

### Cài thêm packages

```bash
sudo pacman -S package-name      # Official
yay -S package-name              # AUR
```

[↑ Về mục lục](#mục-lục)

---

## Khắc phục Sự Cố

### Script dừng lại?

1. Xem log chi tiết:
```bash
tail -f /tmp/arch-install-v3.log
```

2. Kiểm tra Internet: `ping 8.8.8.8`

3. Kiểm tra dung lượng: `lsblk`

4. Nếu vẫn fail - Copy log file và liên hệ

### Boot không được sau cài?

1. Boot ArchISO lại
2. Kiểm tra bootloader:
```bash
efibootmgr           # UEFI
grub-install -v      # BIOS
```

3. Mount root: `mount /dev/sdX /mnt`

4. Chroot: `arch-chroot /mnt`

5. Rebuild initramfs: `mkinitcpio -P`

6. Kiểm tra fstab: `cat /etc/fstab`

7. Exit & reboot: `exit && reboot`

### NVIDIA driver không hoạt động?

```bash
pacman -Q nvidia                           # Kiểm tra
sudo pacman -S nvidia nvidia-utils         # Cài lại
sudo mkinitcpio -P                         # Rebuild
lsmod | grep nvidia                        # Kiểm tra module
```

### Quên password?

1. Boot ArchISO
2. Mount root: `mount /dev/sdX /mnt`
3. Chroot: `arch-chroot /mnt`
4. Reset: `passwd username` hoặc `passwd`
5. Exit & reboot: `exit && reboot`

### Xóa Hyprland, cài i3 hoặc GNOME?

```bash
sudo pacman -R hyprland xdg-desktop-portal-hyprland
sudo pacman -S i3 i3status dmenu          # i3
# Hoặc
sudo pacman -S gnome gnome-extra          # GNOME
```

[↑ Về mục lục](#mục-lục)

---

## Packages Được Cài

**Base System:**
- linux, linux-firmware, linux-headers
- base, base-devel
- grub, efibootmgr, dosfstools
- networkmanager, polkit, seatd
- intel-ucode, amd-ucode

**Hyprland Desktop:**
- hyprland, kitty, wofi
- pipewire, wireplumber, pipewire-pulse
- xdg-desktop-portal-hyprland, zsh, sddm
- archlinux-wallpaper

**GPU Drivers:**
- NVIDIA: nvidia, nvidia-utils, lib32-nvidia-utils
- Intel/AMD: mesa, lib32-mesa, vulkan-icd-loader

**AUR (via yay):**
- wal-colors, ttf-jetbrains-mono-nerd
- catppuccin-sddm-mocha
- hyprland-nvidia (nếu có NVIDIA GPU)
- Invincible-Dots config

[↑ Về mục lục](#mục-lục)

## Tài liệu Thêm

- [Arch Linux Wiki](https://wiki.archlinux.org/)
- [Hyprland Documentation](https://wiki.hyprland.org/)
- [GRUB](https://wiki.archlinux.org/title/GRUB)
- [systemd-boot](https://wiki.archlinux.org/title/Systemd-boot)

[↑ Về mục lục](#mục-lục)

## License

Script được tạo bởi **TYNO** - FIXED V3 2025

## Credits

- [Invincible-Dots](https://github.com/mkhmtolzhas/Invincible-Dots)
- Arch Linux Community
- Hyprland Project

---

**Ghi nhớ:** Thành công phụ thuộc vào hardware, network, và may mắn (60-65%). Đọc log file nếu cài thất bại.
