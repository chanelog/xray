# CHANGELOG v1.3.3 — Fix: multiplex 443 mutusin Xray kalau client gak kirim SNI

## Bug
Di `addon/enable-ssl-multiplex.sh`, logic routing SNI sebelumnya:
```
map $ssl_preread_server_name $ssh_multiplex_backend {
    default        127.0.0.1:$STUNNEL_SSL_PORT;   # SSH-SSL
    $DOMAIN        127.0.0.1:8443;                 # Nginx
}
```
`default` di nginx `map` itu berlaku buat SEMUA nilai yang gak match key
lain — **termasuk SNI KOSONG** (client yang gak kirim TLS SNI extension
sama sekali). Ternyata format VMess yang di-generate script ini
(`gen_vmess_link()` di `lib.sh`) gak punya field `sni` eksplisit dalam
JSON-nya (cuma ada `host`) — banyak app client (v2rayNG dan sejenisnya)
akhirnya gak selalu set SNI otomatis. Begitu multiplex diaktifkan,
koneksi VMess/Xray yang SNI-nya kosong langsung dilempar ke Stunnel4
(SSH-SSL) alih-alih ke Nginx — Xray jadi putus total.

Kelihatan jelas gejalanya: Xray connect normal sebelum multiplex, gak
konek lagi setelah multiplex diaktifkan, dan balik normal begitu
multiplex di-disable.

## Fix
Tambah case eksplisit untuk SNI kosong (`""`) di map, diarahkan ke
Nginx (bukan ke Stunnel4):
```
map $ssl_preread_server_name $ssh_multiplex_backend {
    ""             127.0.0.1:8443;   # SNI kosong -> Nginx (aman buat Xray)
    default        127.0.0.1:777;    # SNI lain (fronting) -> SSH-SSL
    $DOMAIN        127.0.0.1:8443;   # SNI = domain -> Nginx
}
```
Verifikasi otomatis addon (dijalankan di akhir setiap kali addon ini
dieksekusi) sekarang juga ikut mengecek skenario "tanpa SNI", bukan cuma
"SNI domain" dan "SNI fronting" — supaya kelas bug ini otomatis
ketahuan di run berikutnya, gak nunggu laporan manual lagi.

## Validasi
Direproduksi dulu (TLS tanpa SNI -> salah kena Stunnel4/banner SSH),
lalu dibuktikan fix-nya bikin TLS tanpa SNI kembali ke Nginx (HTTP 200),
SEKALIGUS dicek dua skenario lain (SNI domain, SNI fronting) tetap
lolos — tidak ada regresi ke fitur SSH-SSL yang sudah jalan.
