#!/bin/bash
# =============================================================================
# install.sh - master installer for tunnel-suite
#
# Run as root, from inside the extracted tunnel-suite folder:
#   sudo bash install.sh yourdomain.example.com
#
# Safe to re-run: it will not clobber an existing Xray config or existing
# SSH-WS accounts, it only (re)installs packages/services/nginx config.
# =============================================================================
set -e

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOMAIN="${1:-}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
say()  { echo -e "${GREEN}[*]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
die()  { echo -e "${RED}[x]${NC} $*"; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "Jalankan sebagai root (sudo bash install.sh <domain>)"

if [[ -z "$DOMAIN" ]]; then
    read -rp "Masukkan domain yang sudah mengarah ke IP VPS ini: " DOMAIN
fi
[[ -z "$DOMAIN" ]] && die "Domain wajib diisi."

say "Domain    : $DOMAIN"
say "IP publik : $(curl -s -4 --max-time 5 ifconfig.me || echo unknown)"

# ---------------------------------------------------------------------------
# 1. Dependencies
# ---------------------------------------------------------------------------
say "Update & install dependencies (nginx, haproxy, python3, jq, dropbear, stunnel4, ...)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y -qq
apt-get install -y -qq \
    nginx openssh-server dropbear stunnel4 haproxy ca-certificates \
    python3 jq uuid-runtime curl wget unzip socat cron

# ---------------------------------------------------------------------------
# 2. Directories
# ---------------------------------------------------------------------------
mkdir -p /etc/tunnel-suite/ssl
mkdir -p /usr/local/lib/tunnel-suite
echo "$DOMAIN" > /etc/tunnel-suite/domain.conf
touch /etc/tunnel-suite/ssh-users.db

# ---------------------------------------------------------------------------
# 3. Deploy scripts
# ---------------------------------------------------------------------------
say "Deploying scripts..."
install -m 755 "$SELF_DIR/bin/ws-openssh.py" /usr/local/bin/ws-openssh.py
install -m 755 "$SELF_DIR/bin/ws-dropbear.py" /usr/local/bin/ws-dropbear.py
install -m 644 "$SELF_DIR/lib/common.sh" /usr/local/lib/tunnel-suite/common.sh
install -m 644 "$SELF_DIR/lib/ssh_manager.sh" /usr/local/lib/tunnel-suite/ssh_manager.sh
install -m 644 "$SELF_DIR/lib/xray_manager.sh" /usr/local/lib/tunnel-suite/xray_manager.sh
install -m 755 "$SELF_DIR/menu.sh" /usr/local/bin/menu

# ---------------------------------------------------------------------------
# 4. systemd services for the ws-* proxies
# ---------------------------------------------------------------------------
say "Installing systemd services..."
install -m 644 "$SELF_DIR/systemd/ws-openssh.service" /etc/systemd/system/ws-openssh.service
install -m 644 "$SELF_DIR/systemd/ws-dropbear.service" /etc/systemd/system/ws-dropbear.service
systemctl daemon-reload
systemctl enable --now ws-openssh ws-dropbear

# ---------------------------------------------------------------------------
# 5. Dropbear (local, port 143, feeds ws-dropbear.py)
# ---------------------------------------------------------------------------
say "Configuring Dropbear on 127.0.0.1:143 (internal only)..."
if [[ -f /etc/default/dropbear ]]; then
    sed -i 's/^NO_START=.*/NO_START=0/' /etc/default/dropbear || true
    if grep -q '^DROPBEAR_PORT=' /etc/default/dropbear; then
        sed -i 's/^DROPBEAR_PORT=.*/DROPBEAR_PORT=143/' /etc/default/dropbear
    else
        echo 'DROPBEAR_PORT=143' >> /etc/default/dropbear
    fi
    if grep -q '^DROPBEAR_EXTRA_ARGS=' /etc/default/dropbear; then
        sed -i 's/^DROPBEAR_EXTRA_ARGS=.*/DROPBEAR_EXTRA_ARGS="-p 127.0.0.1:143"/' /etc/default/dropbear
    else
        echo 'DROPBEAR_EXTRA_ARGS="-p 127.0.0.1:143"' >> /etc/default/dropbear
    fi
fi
systemctl enable --now dropbear || warn "Gagal enable dropbear, cek manual: systemctl status dropbear"

# ---------------------------------------------------------------------------
# 6. Xray-core (official installer)
# ---------------------------------------------------------------------------
if ! command -v xray >/dev/null 2>&1; then
    say "Installing Xray-core via official XTLS installer..."
    XRAY_INSTALL_TMP="$(mktemp)"
    # raw.githubusercontent.com (not github.com/.../raw/...) - the github.com
    # web-frontend path occasionally 429s with an anti-scraping HTML page,
    # which would otherwise get silently fed into bash as "the script".
    if curl -fsSL "https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh" -o "$XRAY_INSTALL_TMP" \
        && head -n1 "$XRAY_INSTALL_TMP" | grep -q '^#!'; then
        bash "$XRAY_INSTALL_TMP" @ install
    else
        rm -f "$XRAY_INSTALL_TMP"
        die "Gagal download installer Xray dari GitHub (kena rate-limit atau koneksi VPS bermasalah). Tunggu sebentar lalu jalankan ulang install.sh."
    fi
    rm -f "$XRAY_INSTALL_TMP"
else
    say "Xray sudah terpasang, skip instalasi (versi: $(xray version | head -n1))."
fi

if [[ ! -s /usr/local/etc/xray/config.json ]] || ! jq -e '.inbounds' /usr/local/etc/xray/config.json >/dev/null 2>&1; then
    say "Menulis config Xray awal (vmess/vless/trojan/ss atas WS)..."
    install -m 644 "$SELF_DIR/xray/config.json.template" /usr/local/etc/xray/config.json
else
    say "Config Xray sudah ada, tidak ditimpa (akun yang ada tetap aman)."
fi

# ---------------------------------------------------------------------------
# 7. TLS certificate via acme.sh (Let's Encrypt, standalone - stop nginx briefly)
# ---------------------------------------------------------------------------
ACME_HOME="/root/.acme.sh"
ACME_BIN="$ACME_HOME/acme.sh"

if [[ -z "$SSL_EMAIL" ]]; then
    read -rp "Email untuk notifikasi SSL (opsional, Enter = admin@${DOMAIN}): " SSL_EMAIL
    SSL_EMAIL="${SSL_EMAIL:-admin@${DOMAIN}}"
fi

if [[ ! -x "$ACME_BIN" ]]; then
    say "Installing acme.sh (pakai file bundled: acme/acme.sh, tidak download dari internet)..."
    [[ -f "$SELF_DIR/acme/acme.sh" ]] || die "acme/acme.sh tidak ditemukan di paket ini."
    ( cd "$SELF_DIR/acme" && bash ./acme.sh --install --home "$ACME_HOME" --accountemail "$SSL_EMAIL" )
fi
# Explicit: acme.sh defaults to ZeroSSL as CA since v3.0. We pin Let's Encrypt
# so issuance never depends on a ZeroSSL account/EAB step.
"$ACME_BIN" --set-default-ca --server letsencrypt >/dev/null 2>&1 || true

if [[ ! -f /etc/tunnel-suite/ssl/fullchain.pem ]]; then
    say "Menerbitkan sertifikat TLS untuk $DOMAIN (acme.sh standalone, port 80 harus bebas)..."
    systemctl stop nginx 2>/dev/null || true
    if "$ACME_BIN" --issue -d "$DOMAIN" --standalone --server letsencrypt; then
        "$ACME_BIN" --install-cert -d "$DOMAIN" \
            --key-file       /etc/tunnel-suite/ssl/privkey.pem \
            --fullchain-file /etc/tunnel-suite/ssl/fullchain.pem \
            --reloadcmd      "systemctl reload nginx; systemctl restart stunnel4 2>/dev/null"
        say "Sertifikat berhasil diterbitkan & terverifikasi lewat acme.sh (Let's Encrypt)."
        say "Auto-renewal sudah aktif (cron milik acme.sh, reload otomatis lewat --reloadcmd)."
    else
        warn "acme.sh gagal menerbitkan cert (mungkin domain belum resolve ke IP ini, atau port 80 diblok firewall)."
        warn "Membuat sertifikat self-signed sementara supaya Nginx tetap bisa start."
        openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
            -keyout /etc/tunnel-suite/ssl/privkey.pem \
            -out /etc/tunnel-suite/ssl/fullchain.pem \
            -subj "/CN=${DOMAIN}"
        warn "Ganti ke sertifikat asli nanti lewat menu [8] Change Domain setelah DNS beres."
    fi
else
    say "Sertifikat TLS sudah ada, skip penerbitan."
    # still make sure the reload hook is wired even on a re-run
    "$ACME_BIN" --install-cert -d "$DOMAIN" \
        --key-file       /etc/tunnel-suite/ssl/privkey.pem \
        --fullchain-file /etc/tunnel-suite/ssl/fullchain.pem \
        --reloadcmd      "systemctl reload nginx; systemctl restart stunnel4 2>/dev/null" >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------------
# 8. Nginx site config
# ---------------------------------------------------------------------------
say "Configuring Nginx site (443 TLS + 80 ntls)..."
sed "s/__DOMAIN__/${DOMAIN}/g" "$SELF_DIR/nginx/tunnel.conf" > /etc/nginx/conf.d/tunnel.conf
mkdir -p /var/www/html
nginx -t
systemctl enable --now nginx
systemctl restart nginx

# ---------------------------------------------------------------------------
# 9. stunnel4 (SSL mode SSH tunnel, port 777)
# ---------------------------------------------------------------------------
say "Configuring stunnel4 (SSL mode SSH tunnel on port 777)..."
install -m 644 "$SELF_DIR/stunnel/ssh-ssl.conf" /etc/stunnel/ssh-ssl.conf
if [[ -f /etc/default/stunnel4 ]]; then
    sed -i 's/^ENABLED=.*/ENABLED=1/' /etc/default/stunnel4 || echo 'ENABLED=1' >> /etc/default/stunnel4
fi
systemctl enable --now stunnel4 || warn "Gagal enable stunnel4, cek: systemctl status stunnel4"

# ---------------------------------------------------------------------------
# 10. HAProxy - owns public port 443, SNI-routes to stunnel (ssh.<domain>)
#     or Nginx (everything else). Never terminates TLS itself.
# ---------------------------------------------------------------------------
say "Configuring HAProxy (public 443 SNI router)..."
if [[ ! -f /etc/tunnel-suite/haproxy-stats.pass ]]; then
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16 > /etc/tunnel-suite/haproxy-stats.pass
fi
STATS_PASS=$(cat /etc/tunnel-suite/haproxy-stats.pass)
STATS_USER="admin"
sed -e "s/__DOMAIN__/${DOMAIN}/g" \
    -e "s/__STATS_USER__/${STATS_USER}/g" \
    -e "s/__STATS_PASS__/${STATS_PASS}/g" \
    "$SELF_DIR/haproxy/haproxy.cfg" > /etc/haproxy/haproxy.cfg
haproxy -c -f /etc/haproxy/haproxy.cfg || die "Konfigurasi HAProxy tidak valid, cek /etc/haproxy/haproxy.cfg"
systemctl enable --now haproxy
systemctl restart haproxy

# ---------------------------------------------------------------------------
# 11. Daily expiry cleanup (cron)
# ---------------------------------------------------------------------------
say "Memasang cron pembersihan akun expired (harian, jam 00:30)..."
cat > /etc/cron.d/tunnel-suite-expiry <<EOF
30 0 * * * root /usr/local/lib/tunnel-suite/ssh_manager.sh cleanup >/var/log/tunnel-suite-cleanup.log 2>&1
31 0 * * * root /usr/local/lib/tunnel-suite/xray_manager.sh cleanup >>/var/log/tunnel-suite-cleanup.log 2>&1
EOF
chmod 644 /etc/cron.d/tunnel-suite-expiry
# make the two library files executable directly too (cleanup mode entrypoint)
chmod +x /usr/local/lib/tunnel-suite/ssh_manager.sh /usr/local/lib/tunnel-suite/xray_manager.sh

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo
say "Instalasi selesai!"
echo "-------------------------------------------------------------"
echo " Domain         : $DOMAIN"
echo " Buka menu      : sudo menu"
echo
echo " PENTING - tambahkan 1 DNS record lagi (A record, IP sama):"
echo "   ssh.$DOMAIN  ->  $(curl -s -4 --max-time 5 ifconfig.me || echo 'IP-VPS-ini')"
echo " (dipakai HAProxy untuk mengenali trafik SSH-SSL lewat port 443)"
echo
echo " Port publik yang perlu dibuka di firewall/provider VPS:"
echo "   80   -> Nginx (ntls / ACME challenge)"
echo "   443  -> HAProxy (SNI router: ssh.$DOMAIN -> SSH-SSL, domain biasa -> Nginx)"
echo "   777  -> stunnel (SSH SSL langsung, akses alternatif tanpa lewat HAProxy)"
echo
echo " HAProxy stats (dari VPS ini saja): curl -u admin:${STATS_PASS} http://127.0.0.1:9000/"
echo "-------------------------------------------------------------"
