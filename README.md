# CHANELOG VPN SCRIPT
## Script Tunneling V2Ray/Xray - VMess & VLess WebSocket

[![GitHub](https://img.shields.io/badge/Bin%20Source-chanelog%2Fbin-blue)](https://github.com/chanelog/bin)

---

## 📦 Fitur

- ✅ **VMess WebSocket TLS** (port 443)
- ✅ **VMess WebSocket non-TLS** (port 80)
- ✅ **VLess WebSocket TLS** (port 443)
- ✅ **VLess WebSocket non-TLS** (port 80)
- ✅ **SSL Otomatis** via acme.sh (Let's Encrypt / ZeroSSL)
- ✅ **Nginx** sebagai reverse proxy
- ✅ **Dropbear SSH** (port 442, 109, 143)
- ✅ **Manajemen akun** lengkap (buat, info, detail, hapus, perpanjang, renew)
- ✅ **Verifikasi domain** wajib saat install
- ✅ **Ganti domain** + auto SSL baru
- ✅ **Uninstall** bersih
- ✅ Binary dari repository [chanelog/bin](https://github.com/chanelog/bin)

---

## 🚀 Cara Install

```bash
# Upload semua file ke VPS, lalu:
chmod +x install.sh
bash install.sh
```

Saat install, script akan:
1. **Meminta domain** → wajib diisi
2. **Memverifikasi DNS** → domain harus mengarah ke IP server
3. Install semua komponen otomatis
4. Request SSL certificate via acme.sh

---

## 📂 Struktur File

```
vpn-script/
├── install.sh          # Installer utama
├── menu.sh             # Menu utama (jalankan: vpn)
├── lib.sh              # Library / fungsi helper
└── menu/
    ├── vmess.sh        # Menu VMess
    ├── vless.sh        # Menu VLess
    ├── nginx.sh        # Menu Nginx
    ├── dropbear.sh     # Menu Dropbear
    ├── sysinfo.sh      # Info sistem
    ├── changedomain.sh # Ganti domain
    └── uninstall.sh    # Uninstall
```

---

## 🗃️ Binary dari chanelog/bin

| File | Keterangan |
|------|------------|
| `Xray-linux-64.zip` | Xray core (amd64) |
| `Xray-linux-arm64-v8a.zip` | Xray core (ARM64) |
| `acme.sh` | SSL certificate manager |
| `nginx-1.28.0.tar.gz` | Web server / reverse proxy |
| `dropbear-master.zip` | SSH server ringan |
| `jq-linux-amd64` | JSON processor |
| `install-release.sh` | Xray installer helper |

---

## 🔧 Konfigurasi Port

| Layanan | Port |
|---------|------|
| HTTP (redirect) | 80 |
| HTTPS / VMess-VLess TLS | 443 |
| VMess-VLess non-TLS | 80 |
| Dropbear SSH | 442, 109, 143 |
| Xray VMess TLS (internal) | 10001 |
| Xray VLess TLS (internal) | 10002 |
| Xray VMess nTLS (internal) | 10003 |
| Xray VLess nTLS (internal) | 10004 |

---

## 📋 Menu Utama

```
[1] VMess WebSocket  → Buat/Info/Detail/Hapus/Perpanjang/Renew
[2] VLess WebSocket  → Buat/Info/Detail/Hapus/Perpanjang/Renew
[3] Nginx Management → Start/Stop/Restart/Reload/Renew SSL
[4] Dropbear SSH     → Start/Stop/Restart/Ubah Port
[5] System Info      → Info lengkap VPS + services
[6] Change Domain    → Ganti domain + auto SSL baru
[7] Uninstall        → Hapus semua komponen
```

---

## 🔗 Format Link

**VMess TLS:**
```
vmess://eyJ2IjoiMiIsInBzIjoiLi4uIn0=
```

**VLess TLS:**
```
vless://UUID@domain.com:443?encryption=none&security=tls&type=ws&path=/vless-ws#name
```

**VMess non-TLS:**
```
vmess://eyJ2IjoiMiIsInBzIjoiLi4uIn0=
```

**VLess non-TLS:**
```
vless://UUID@domain.com:80?encryption=none&security=none&type=ws&path=/vless-ntls#name
```

---

## 🛡️ Persyaratan

- OS: Ubuntu 20.04 / 22.04 / Debian 10 / 11
- RAM: Minimal 256MB
- Domain yang sudah diarahkan ke IP server (A Record)
- Port 80 terbuka (untuk verifikasi SSL acme.sh)

---

## ⚡ Setelah Install

```bash
vpn          # Buka menu utama
```

Database akun tersimpan di:
- `/etc/vpn-script/db/vmess.db`
- `/etc/vpn-script/db/vless.db`
