# CHANGELOG v1.3.0 — Multiplex Port 443 (Xray/WS + SSH-SSL raw)

## Fitur baru: `addon/enable-ssl-multiplex.sh`

Port 443 sekarang bisa dipakai BARENG oleh:
- **Xray (VMess/VLess/Trojan/SS) + SSH-WS TLS** (`/ssh-ws`, `/ssh-ws-ssh`) — tetap
  ditangani Nginx seperti biasa, SNI harus = domain asli.
- **SSH-SSL murni** (SNI-only, TANPA payload HTTP) — diteruskan langsung ke
  Stunnel4 → Dropbear (raw), SNI bebas/acak.

### Cara kerja
Nginx `stream` module (`ssl_preread`) mengintip SNI dari ClientHello TLS
SEBELUM didekripsi, lalu meneruskan koneksi (masih terenkripsi) ke salah
satu dari dua tujuan berdasarkan SNI:
- SNI == domain asli → Nginx internal (`127.0.0.1:8443`)
- SNI lainnya (termasuk kosong / fronting acak) → Stunnel4 (`127.0.0.1:777`)

### Prasyarat PENTING: DNS-only, bukan Proxied Cloudflare
Fitur ini HANYA berguna kalau domain **DNS-only** (awan abu-abu) di Cloudflare
(atau DNS provider lain tanpa proxy). Kalau domain di-proxy (awan oranye),
Cloudflare hanya meneruskan trafik HTTP/HTTPS/WebSocket ke origin — trafik
SSH-SSL mentah akan ditolak/difilter di edge Cloudflare SEBELUM sempat
sampai ke fitur multiplex ini. Cloudflare proxy juga tidak mendukung port
2080 (salah satu port SSH-WS nTLS di script ini) — hanya 80/8080/8880/
2052/2082/2086/2095 (HTTP) dan 443/2053/2083/2087/2096/8443 (HTTPS).

### Peringatan
User yang connect ke `/ssh-ws` atau `/ssh-ws-ssh` (mode payload) dengan SNI
fronting/acak (bukan domain asli persis) akan GAGAL setelah fitur ini aktif
— karena Nginx tidak akan pernah melihat koneksinya (dialihkan ke jalur
SSH-SSL). Pastikan user pakai SNI = domain asli untuk mode payload WS.

### Keamanan
Full backup (`nginx.conf` + `xray.conf`) sebelum perubahan, `nginx -t` +
reload, lalu verifikasi FUNGSIONAL nyata (bukan cuma syntax check): test
SNI domain harus dibalas HTTP oleh Nginx, test SNI acak harus dibalas
banner SSH oleh Dropbear. Kalau salah satu gagal, rollback otomatis ke
config semula.

### Cara pakai
```bash
bash /etc/vpn-script/addon/enable-ssl-multiplex.sh          # aktifkan
bash /etc/vpn-script/addon/enable-ssl-multiplex.sh disable  # matikan, balik normal
```

`regenerate_nginx_conf()` di `lib.sh` sekarang otomatis mendeteksi apakah
multiplex aktif (`/etc/nginx/stream.d/ssh-ssl-multiplex.conf` ada) dan
menyesuaikan bind Nginx https (internal `127.0.0.1:8443` vs public `443`)
supaya regenerasi config di masa depan (misal dari addon SSH-WS) tidak
diam-diam membatalkan setup multiplex ini.

Tervalidasi end-to-end di sandbox: nginx + stream module asli + stunnel4
asli, 3 skenario (SNI domain, SNI acak, tanpa SNI) — semua lolos.
