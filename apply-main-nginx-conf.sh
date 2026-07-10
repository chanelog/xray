#!/bin/bash
# apply-main-nginx-conf.sh
# Mengambil nginx.conf utama TERBARU dari repo (chanelog/xray) dan
# memasangnya ke server yang SUDAH JALAN, tanpa perlu re-run install.sh penuh.
# Aman: backup dulu, validasi "nginx -t", rollback otomatis kalau gagal.

RAW="https://raw.githubusercontent.com/chanelog/xray/main"

if [[ $EUID -ne 0 ]]; then
  echo "Jalankan sebagai root!"
  exit 1
fi

NGINX_MAIN_CONF="/etc/nginx/nginx.conf"
NGINX_MAIN_BACKUP="${NGINX_MAIN_CONF}.bak.$(date +%s)"

if [[ ! -f "$NGINX_MAIN_CONF" ]]; then
  echo "[ERROR] $NGINX_MAIN_CONF tidak ditemukan. Nginx belum terinstall?"
  exit 1
fi

cp "$NGINX_MAIN_CONF" "$NGINX_MAIN_BACKUP"
echo "[*] Backup config lama: $NGINX_MAIN_BACKUP"

NGINX_TMP=$(mktemp)
echo "[*] Download nginx.conf dari $RAW/nginx/nginx.conf ..."
if ! wget -q --timeout=30 "$RAW/nginx/nginx.conf" -O "$NGINX_TMP" || [[ ! -s "$NGINX_TMP" ]]; then
  echo "[ERROR] Gagal download nginx.conf dari repo. Cek koneksi / URL repo."
  rm -f "$NGINX_TMP"
  exit 1
fi

cp "$NGINX_TMP" "$NGINX_MAIN_CONF"
rm -f "$NGINX_TMP"

if nginx -t 2>/dev/null; then
  systemctl reload nginx 2>/dev/null || systemctl restart nginx 2>/dev/null
  echo "[OK] nginx.conf baru terpasang & Nginx sudah di-reload."
else
  echo "[ERROR] 'nginx -t' gagal dengan config baru, mengembalikan config asal..."
  cp "$NGINX_MAIN_BACKUP" "$NGINX_MAIN_CONF"
  systemctl reload nginx 2>/dev/null
  echo "[WARN] Config dikembalikan seperti semula. Jalankan 'nginx -t' manual untuk lihat errornya."
  exit 1
fi
