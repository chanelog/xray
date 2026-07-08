# Tunnel Suite - SSH-WS (TLS/ntls/SSL) + Xray Manager

Paket lengkap untuk VPS Debian/Ubuntu: SSH-over-WebSocket (3 mode koneksi:
TLS, ntls, SSL) + Xray-core (VMess, VLess, Trojan, Shadowsocks di atas
WebSocket), dibungkus dengan menu interaktif ala screenshot yang kamu kirim.

Semua kode di sini **ditulis ulang dari nol**, hanya memakai software
open-source resmi (Xray-core dari XTLS, Nginx, Dropbear, stunnel4) - bukan
hasil copy-paste script pihak ketiga yang tidak jelas asal-usulnya.

## Kenapa dibuat ulang, bukan cuma dipakai file lama kamu?

File `ws-openssh`, `ws-dropbear`, `ws-stunnel` yang sudah kamu punya ditulis
dengan sintaks **Python 2** (`print log`, `import thread`, dst). Debian 11/12
modern sudah tidak menyediakan `python2` secara default, jadi service itu
kemungkinan besar **tidak jalan** kalau langsung dipakai. Di paket ini semua
sudah ditulis ulang untuk **Python 3** dan sudah diuji jalan (handshake +
passthrough data + proteksi anti open-relay).

## Struktur folder

```
tunnel-suite/
├── install.sh                  <- installer utama, jalankan ini
├── menu.sh                     <- menu interaktif (di-copy ke /usr/local/bin/menu)
├── bin/
│   ├── ws-openssh.py           <- proxy WS -> sshd lokal (port 700 internal)
│   └── ws-dropbear.py          <- proxy WS -> dropbear lokal (port 701 internal)
├── lib/
│   ├── common.sh                <- helper bersama (warna, status service, dsb)
│   ├── ssh_manager.sh            <- kelola akun SSH-WS (linux user + expiry)
│   └── xray_manager.sh           <- kelola akun VMess/VLess/Trojan/SS (WS+gRPC)
├── systemd/
│   ├── ws-openssh.service
│   └── ws-dropbear.service
├── nginx/tunnel.conf            <- vhost 8443-internal (TLS) + 80 publik (ntls)
├── haproxy/haproxy.cfg          <- router SNI di port 443 publik
├── stunnel/ssh-ssl.conf         <- mode "SSL" (stunnel bungkus SSH langsung)
├── acme/acme.sh                 <- client acme.sh (bahan kamu, dibundel apa adanya)
└── xray/config.json.template    <- config awal Xray (vmess/vless/trojan/ss, WS+gRPC)
```

## Arsitektur

**HAProxy memegang port 443 publik.** Ia tidak pernah membuka TLS-nya - cuma
mengintip field SNI di ClientHello (bagian yang memang belum terenkripsi),
lalu meneruskan koneksi mentah-mentah (masih terenkripsi) ke backend yang
tepat. Ini supaya SSH-SSL (stunnel) BISA JUGA diakses lewat port 443, bukan
cuma lewat port 777 - berguna kalau jaringan si user cuma buka port 443.

```
                              ┌─ SNI = ssh.<domain>  ──► stunnel :777 ──► sshd :22
Client ──► HAProxy :443 (publik) ┤
                              └─ SNI lainnya (domain biasa) ──► Nginx :8443 (internal)
                                                                     │
                                                                     ├─ /vmess       → Xray :10001
                                                                     ├─ /vless       → Xray :10002
                                                                     ├─ /trojan-ws   → Xray :10003
                                                                     ├─ /trojan-grpc → Xray :10005 (gRPC)
                                                                     ├─ /ss-ws       → Xray :10004
                                                                     ├─ /ss-grpc     → Xray :10006 (gRPC)
                                                                     ├─ /ssh-ws      → ws-openssh.py :700 → sshd :22
                                                                     └─ /dropbear-ws → ws-dropbear.py :701 → dropbear :143

Client ──► Nginx :80 (ntls, publik, tak lewat HAProxy) ──► path routing sama seperti di atas
Client ──► stunnel :777 (publik, langsung, tanpa HAProxy) ──► sshd :22
```

## 3 mode SSH

| Mode | Cara akses | Kapan dipakai |
|------|-----------|---------------|
| TLS  | host `<domain>` port 80, path `/ssh-ws`, plain ws | dipakai di belakang CDN/Cloudflare, atau saat TLS di-block ISP |
| ntls | (sama seperti di atas, lihat tabel port di bawah) | |
| SSL  | host `<domain>` port 777 (langsung), **atau** SNI `ssh.<domain>` port 443 (lewat HAProxy) | app yang cuma bisa keluar lewat port 443, atau yang support mode "SSH SSL" |

> **Catatan DNS**: selain A record untuk `<domain>`, tambahkan juga A record
> untuk `ssh.<domain>` (IP sama) supaya rute HAProxy di atas berfungsi.
> `install.sh` akan mengingatkan ini di akhir instalasi.

Xray (VMess/VLess/Trojan/Shadowsocks) lewat WebSocket **dan** gRPC, semua di
belakang Nginx:

| Protokol         | Transport | Path/Service    | Port internal |
|------------------|-----------|-----------------|---------------|
| VMess            | WS        | /vmess          | 127.0.0.1:10001 |
| VLess            | WS        | /vless          | 127.0.0.1:10002 |
| Trojan           | WS        | /trojan-ws      | 127.0.0.1:10003 |
| Trojan           | gRPC      | trojan-grpc     | 127.0.0.1:10005 |
| Shadowsocks      | WS        | /ss-ws          | 127.0.0.1:10004 |
| Shadowsocks      | gRPC      | ss-grpc         | 127.0.0.1:10006 |
| SSH-WS           | WS        | /ssh-ws         | 127.0.0.1:700   |
| Dropbear-WS      | WS        | /dropbear-ws    | 127.0.0.1:701   |

Di menu, saat bikin akun Trojan/Shadowsocks kamu akan ditanya mau pakai
transport **WS** atau **gRPC** (VMess/VLess tetap WS saja, sesuai label menu
di gambar referensi kamu).

## Instalasi

1. Pastikan domain sudah di-pointing (A record) ke IP VPS ini, **plus** satu
   A record lagi untuk `ssh.<domain>` (IP sama) - dipakai HAProxy untuk
   mengenali trafik SSH-SSL yang lewat port 443.
2. Upload folder `tunnel-suite/` ke VPS (scp/sftp/git), lalu:

```bash
cd tunnel-suite
sudo bash install.sh domainkamu.example.com
```

3. Buka firewall/security group provider untuk port: **22, 80, 443, 777**
   (port 8443 dan port internal Xray/dropbear TIDAK perlu dibuka - itu hanya
   dipakai secara lokal oleh Nginx/HAProxy).
4. Selesai instalasi, buka menu:

```bash
sudo menu
```

## Xray - dari mana bahannya?

Xray-core di-install lewat **installer resmi XTLS** (bukan pihak ketiga):

```
https://github.com/XTLS/Xray-install
```

`install.sh` di paket ini otomatis menjalankan installer resmi tersebut, lalu
menulis `config.json` awal (kosong, tanpa akun) dengan 4 inbound WS di
belakang Nginx. Akun ditambahkan lewat menu, bukan dengan edit config manual.

## Sertifikat TLS lewat acme.sh

Verifikasi & penerbitan sertifikat pakai **acme.sh** (bukan certbot), sesuai
konvensi yang biasa dipakai di script tunneling seperti ini. Client-nya pakai
`acme/acme.sh` (v3.1.4) yang kamu siapkan sendiri - **dibundel apa adanya di
paket ini, `install.sh` TIDAK download acme.sh dari internet.**

- `install.sh` menjalankan `acme/acme.sh --install` (persis metode resmi
  "manual install": `cd acme.sh && ./acme.sh --install`) untuk memasangnya
  ke `/root/.acme.sh`.
- CA di-pin ke **Let's Encrypt** secara eksplisit (`--server letsencrypt`) -
  acme.sh v3.1.4 defaultnya ZeroSSL, yang butuh langkah registrasi akun
  tambahan; dengan di-pin begini, tidak perlu urus itu.
- Penerbitan pakai mode **standalone** (`--standalone`, butuh port 80 bebas
  sebentar - makanya Nginx di-stop sesaat lalu distart lagi otomatis).
- Cert di-deploy ke `/etc/tunnel-suite/ssl/{fullchain,privkey}.pem` lewat
  `--install-cert`, sekalian pasang `--reloadcmd` supaya **setiap kali acme.sh
  memperpanjang cert (otomatis, lewat cron miliknya sendiri), Nginx & stunnel4
  langsung di-reload/restart tanpa perlu campur tangan manual.**
- Kalau penerbitan gagal (biasanya karena DNS belum propagate), installer
  otomatis bikin sertifikat self-signed sementara supaya Nginx tetap bisa
  jalan - lalu kamu tinggal reissue lewat menu **[8] Change Domain** setelah
  DNS-nya beres.
- Saat instalasi kamu akan ditanya email untuk notifikasi SSL (opsional,
  Enter saja untuk pakai `admin@<domain>`).

## Catatan Shadowsocks WS

Xray mendukung Shadowsocks multi-user di atas WebSocket, tapi ini adalah
fitur khas Xray/V2Ray - aplikasi Shadowsocks generik (Shadowsocks-Android,
dsb) **tidak** paham parameter `type=ws&host=...&path=...`. Untuk protokol
ini pakai client yang kompatibel Xray, misalnya **NekoBox** atau **v2rayNG**
(pilih profil Shadowsocks lalu isi transport WebSocket manual).

## Keamanan yang sudah dijaga

- `ws-openssh.py` / `ws-dropbear.py` hanya mau connect ke `127.0.0.1` /
  `localhost` walau client mengirim header `X-Real-Host` custom - jadi proxy
  ini **tidak** bisa dipakai sebagai open relay ke host sembarang di internet.
- Semua service internal (700, 701, 10001-10006, 8443) hanya listen di
  `127.0.0.1`, tidak exposed langsung ke publik - satu-satunya pintu masuk
  publik adalah HAProxy (443), Nginx (80), dan stunnel (777).
- HAProxy tidak pernah menyimpan/memegang private key TLS - ia murni
  meneruskan byte terenkripsi berdasarkan SNI, jadi kunci privat cuma ada di
  Nginx dan stunnel (prinsip least-privilege).
- Expiry akun (SSH maupun Xray) dibersihkan otomatis tiap hari jam 00:30
  lewat cron (`/etc/cron.d/tunnel-suite-expiry`).
- Halaman statistik HAProxy (`127.0.0.1:9000`) hanya bisa diakses dari VPS itu
  sendiri dan pakai password acak yang dibuat saat instalasi
  (`/etc/tunnel-suite/haproxy-stats.pass`).

## Menu

Menu `sudo menu` menampilkan dashboard (domain, IP, OS, CPU, RAM, disk,
uptime, status tiap service termasuk HAProxy, jumlah akun aktif) persis
seperti contoh screenshot, dengan opsi:

1. SSHWS - buat/list/perpanjang/hapus akun SSH-WS
2. VMess WS
3. VLess WS
4. Trojan WS/gRPC - pilih transport WS atau gRPC saat membuat akun
5. Shadowsocks WS/gRPC - pilih transport WS atau gRPC saat membuat akun
6. Nginx Management (restart/reload/test config/log + kontrol HAProxy)
7. Dropbear Management (restart/ganti port)
8. Change Domain (update domain, haproxy.cfg, + reissue sertifikat TLS lewat acme.sh)
9. Update Script (instruksi update manual, lihat catatan di menu)
10. Uninstall (hapus semua komponen tunnel-suite termasuk HAProxy)
11. Status Layanan
12. System Info

## Kredit

- Xray-core & installer resmi: XTLS/Xray-core, XTLS/Xray-install
- acme.sh: acmesh-official/acme.sh (penerbitan & auto-renewal sertifikat TLS)
- Nginx, Dropbear, stunnel4, HAProxy: proyek open-source masing-masing (paket distro)
- Sisanya (menu, manajer akun, proxy WS python3, config HAProxy): ditulis khusus untuk paket ini
