# CHANGELOG v1.1.6 — Fix SSH-WS (TLS/nTLS/SSL) + Stunnel4 + HAProxy

## Root cause utama

`WS_DROPBEAR_PORT`, `WS_OPENSSH_PORT`, `WS_STUNNEL_PORT` dipakai di seluruh
`addon/install-sshws.sh` tapi **tidak pernah didefinisikan** di `lib.sh`.
Efeknya menjalar ke banyak tempat:

1. **`stunnel.conf` rusak** → baris `connect = 127.0.0.1:$WS_STUNNEL_PORT`
   jadi `connect = 127.0.0.1:` (port kosong) → stunnel4 gagal parse config
   → **stunnel4 tidak bisa start**. Ini penyebab langsung "stunnel4 belum on".
2. Nginx `location /ssh-ws` di SEMUA 6 server block (80, 8880, 8080, 2080,
   2082, 443) masih `proxy_pass http://127.0.0.1:700;` — port lama milik
   `ws-proxy.py` (Python 2) yang **sudah dihapus** oleh `install-sshws.sh`.
   Backend baru (`ws-dropbear`) jalan di port 2095, bukan 700 → SSH-WS
   nTLS **maupun** TLS sama-sama nyasar ke port mati.
3. `location /ssh-ws-ssh` (backend OpenSSH, port 2093) **tidak pernah ada**
   di Nginx sama sekali, padahal `menu/sshws.sh` sudah mengiklankannya di
   semua port. Sebelumnya kode hanya *warning*, tidak benar-benar memperbaiki.
4. **HAProxy vs Stunnel4 rebutan port 445** — `addon/haproxy-sshws-ssl.sh`
   bind ke `0.0.0.0:445 ssl`, port yang **identik** dengan Stunnel4
   (`STUNNEL_SSL_PORT=445`). Siapa pun yang start belakangan pasti gagal
   bind ("Address already in use").
5. `addon/haproxy-sshws-ssl.sh` **tidak pernah dipanggil dari mana pun**
   (tidak di `install.sh`, tidak di `menu/haproxy.sh`, tidak di `menu.sh`).
   Tombol "Start HAProxy" cuma `systemctl start haproxy` — pasti gagal
   karena config-nya memang belum pernah dibuat.
6. Bug tambahan di config HAProxy: `log local0 debug` adalah **syntax
   invalid** (haproxy menolak start), dan `timeout client` salah
   diletakkan di `backend` (harusnya di `frontend`).
7. `MANAGED_SERVICES` & `service_display_name()` di `lib.sh` masih
   merujuk service lama `ws-proxy` yang sudah dihapus.

## Perbaikan

- **`lib.sh`**
  - Definisikan `WS_DROPBEAR_PORT=2095`, `WS_OPENSSH_PORT=2093`,
    `WS_STUNNEL_PORT=700`, `HAPROXY_SSL_PORT=446` (baru, terpisah dari
    Stunnel4 di 445 supaya keduanya tidak bentrok).
  - Tambah fungsi `regenerate_nginx_conf()` — single source of truth
    config Nginx (backup otomatis + `nginx -t` + rollback bila error),
    dipakai untuk retrofit VPS yang sudah kadung ke-install versi lama.
  - `MANAGED_SERVICES` & `service_display_name()` diupdate ke
    `ws-dropbear`, `ws-openssh`, `ws-stunnel`.
- **`install.sh`** — `/ssh-ws` di 6 server block diarahkan ke port 2095
  (bukan 700), ditambah `/ssh-ws-ssh` → 2093 di 6 server block yang sama.
  Ringkasan akhir instalasi juga tidak lagi cek service `ws-proxy` yang
  sudah tidak ada.
- **`addon/install-sshws.sh`** — bagian cek Nginx sekarang benar-benar
  memanggil `regenerate_nginx_conf "$DOMAIN"` (bukan cuma warning) kalau
  terdeteksi config lama/rusak.
- **`addon/haproxy-sshws-ssl.sh`** — pindah ke port 446 (bebas konflik
  dengan Stunnel4), fix syntax `log` yang invalid, fix `timeout client`
  yang salah tempat, pakai variabel dari `lib.sh` (bukan hardcode).
- **`menu/haproxy.sh`** — "Start HAProxy" sekarang auto-provisioning
  (menjalankan `addon/haproxy-sshws-ssl.sh` dulu) kalau config belum ada.

## Hasil setelah fix (tervalidasi dengan nginx/haproxy/stunnel4 asli)

| Jalur                          | Sebelum          | Sesudah                        |
|--------------------------------|------------------|---------------------------------|
| `/ssh-ws` (semua port)         | -> :700 (mati)   | -> ws-dropbear :2095 ✅         |
| `/ssh-ws-ssh` (semua port)     | tidak ada        | -> ws-openssh :2093 ✅          |
| Stunnel4 SSL (445)             | gagal start      | -> ws-stunnel :700 ✅           |
| HAProxy SSL (446, opsional)    | orphan/bentrok   | -> ws-stunnel :700 ✅           |
