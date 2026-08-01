# CHANGELOG v1.4.0 — Multiplex Port 443 v2: HAProxy (bukan Nginx stream)

## Kenapa diganti
Versi 1 (v1.3.0-v1.3.3) pakai Nginx `stream` module + `ssl_preread` buat
baca SNI. Setelah berkali-kali gagal reproduksi & fix bug "Connection
reset" yang muncul spesifik pas trafik Xray sungguhan (bukan cuma
handshake), diputuskan ganti pendekatan sepenuhnya: **HAProxy TCP mode +
inspeksi SNI** (`req.ssl_sni`), teknik yang jauh lebih matang/lazim
dipakai khusus buat kasus "satu port banyak protokol berdasar SNI".

## Perubahan
- `addon/enable-ssl-multiplex.sh` ditulis ulang total: HAProxy sekarang
  yang pegang port 443 publik (`frontend multiplex_443`), bukan Nginx
  stream lagi. Nginx tetap cuma nangani HTTP/WS di internal
  `127.0.0.1:8443`, gak berubah dari sisi Nginx.
- Config disisipkan ke `haproxy.cfg` yang sudah ada (marker-based,
  idempotent — sama pola kayak fix HAProxy sebelumnya), BUKAN file
  terpisah yang di-`include` (HAProxy gak punya directive itu).
- `lib.sh`: `regenerate_nginx_conf()` sekarang pakai marker generik
  `/etc/vpn-script/.multiplex-443-active` (bukan cek file Nginx
  stream.d lagi) — kompatibel ke depan kalau ganti mekanisme lagi.
- Routing logic SAMA seperti sebelumnya (pelajaran dari bug SNI-kosong
  tetap dipertahankan):
  - SNI == domain asli, ATAU SNI kosong -> Nginx (Xray/WS)
  - SNI lainnya (fronting acak) -> Stunnel4 -> Dropbear (SSH-SSL)

## Validasi
- Config `haproxy -c` valid.
- 3 skenario SNI dasar (domain/kosong/fronting) tervalidasi lolos.
- **Xray asli (bukan simulasi) + cek koneksi internet sungguhan
  (`curl` via SOCKS -> VMess -> HAProxy multiplex -> Nginx -> Xray ->
  api.github.com) berhasil dapat response valid** — skenario PERSIS
  yang gagal total di versi Nginx stream sebelumnya.
- Catatan jujur: testing sustained/berulang di sandbox saya sendiri
  terganggu instabilitas infrastruktur sandbox (proses mati sendiri
  berkali-kali, bukan soal desain), jadi validasi akhir tetap perlu
  dilakukan di VPS asli yang stabil.

## Cara pakai
```bash
bash /etc/vpn-script/addon/enable-ssl-multiplex.sh          # aktifkan
bash /etc/vpn-script/addon/enable-ssl-multiplex.sh disable  # matikan
```
Sama seperti sebelumnya: full backup + validasi syntax (`haproxy -c`,
`nginx -t`) + verifikasi FUNGSIONAL (3 skenario SNI) + rollback otomatis
kalau salah satu gagal.
