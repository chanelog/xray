#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - INSTALLER
#   Repository: https://github.com/chanelog/bin
# ============================================================

REPO="https://raw.githubusercontent.com/chanelog/bin/main"
SCRIPT_DIR="/etc/vpn-script"
BIN_DIR="/usr/local/bin"

# ─── Colors ────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Check Root ────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}[ERROR]${NC} Script harus dijalankan sebagai root!"
  exit 1
fi

# ─── Check OS ──────────────────────────────────────────────
if [[ ! -f /etc/debian_version ]] && [[ ! -f /etc/ubuntu_release ]]; then
  . /etc/os-release
  if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
    echo -e "${RED}[ERROR]${NC} Script hanya mendukung Ubuntu/Debian!"
    exit 1
  fi
fi

# ─── Banner ────────────────────────────────────────────────
clear
echo -e "${CYAN}"
cat <<'EOF'
  ██████╗██╗  ██╗ █████╗ ███╗   ██╗███████╗██╗      ██████╗  ██████╗ 
 ██╔════╝██║  ██║██╔══██╗████╗  ██║██╔════╝██║     ██╔═══██╗██╔════╝ 
 ██║     ███████║███████║██╔██╗ ██║█████╗  ██║     ██║   ██║██║  ███╗ 
 ██║     ██╔══██║██╔══██║██║╚██╗██║██╔══╝  ██║     ██║   ██║██║   ██║ 
 ╚██████╗██║  ██║██║  ██║██║ ╚████║███████╗███████╗╚██████╔╝╚██████╔╝ 
  ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝╚══════╝ ╚═════╝  ╚═════╝  
EOF
echo -e "${NC}"
echo -e "${WHITE}          VPN TUNNEL SCRIPT - XRAY/V2RAY EDITION${NC}"
echo -e "${YELLOW}          ════════════════════════════════════════${NC}"
echo ""

# ─── Input Domain ──────────────────────────────────────────
ask_domain() {
  while true; do
    echo -e "${CYAN}[*]${NC} Masukkan domain yang sudah diarahkan ke IP server ini:"
    echo -ne "  ${WHITE}Domain${NC}: "
    read -r DOMAIN
    DOMAIN=$(echo "$DOMAIN" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    if [[ -z "$DOMAIN" ]]; then
      echo -e "${RED}[ERROR]${NC} Domain tidak boleh kosong!"
      continue
    fi

    # Validate domain format
    if ! echo "$DOMAIN" | grep -qP '^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'; then
      echo -e "${RED}[ERROR]${NC} Format domain tidak valid!"
      continue
    fi

    echo -e "${CYAN}[*]${NC} Memverifikasi domain ${WHITE}$DOMAIN${NC} → IP server..."
    SERVER_IP=$(curl -s4 https://ifconfig.me 2>/dev/null || curl -s4 https://api.ipify.org 2>/dev/null)
    DOMAIN_IP=$(dig +short "$DOMAIN" A 2>/dev/null | tail -1)

    if [[ -z "$SERVER_IP" ]]; then
      echo -e "${YELLOW}[WARN]${NC} Tidak bisa mengambil IP server, melewati verifikasi DNS..."
      break
    fi

    if [[ -z "$DOMAIN_IP" ]]; then
      echo -e "${RED}[ERROR]${NC} Domain ${WHITE}$DOMAIN${NC} tidak ditemukan! Pastikan DNS sudah benar."
      echo -ne "  Lanjutkan meski DNS belum propagasi? [y/N]: "
      read -r FORCE
      if [[ "$FORCE" =~ ^[Yy]$ ]]; then
        break
      fi
      continue
    fi

    if [[ "$DOMAIN_IP" == "$SERVER_IP" ]]; then
      echo -e "${GREEN}[OK]${NC} Domain ${WHITE}$DOMAIN${NC} → ${GREEN}$SERVER_IP${NC} (VERIFIED ✓)"
      break
    else
      echo -e "${RED}[ERROR]${NC} Domain mengarah ke ${WHITE}$DOMAIN_IP${NC}, bukan ${WHITE}$SERVER_IP${NC}"
      echo -ne "  Lanjutkan meski IP tidak cocok? [y/N]: "
      read -r FORCE
      if [[ "$FORCE" =~ ^[Yy]$ ]]; then
        break
      fi
    fi
  done

  echo "$DOMAIN" > /tmp/vpn_domain.tmp
}

# ─── Install Dependencies ──────────────────────────────────
install_deps() {
  echo -e "\n${CYAN}[*]${NC} Menginstall dependensi sistem..."
  apt-get update -qq
  apt-get install -y -qq \
    curl wget unzip zip socat tar \
    dnsutils net-tools \
    openssl ca-certificates \
    build-essential libssl-dev \
    cron vnstat fail2ban \
    jq bc uuid-runtime \
    iptables-persistent netfilter-persistent 2>/dev/null
  echo -e "${GREEN}[OK]${NC} Dependensi terinstall"
}

# ─── Install Nginx ─────────────────────────────────────────
install_nginx() {
  echo -e "\n${CYAN}[*]${NC} Menginstall Nginx dari repository chanelog/bin..."
  cd /tmp
  wget -q "$REPO/nginx-1.28.0.tar.gz" -O nginx.tar.gz
  if [[ $? -ne 0 ]]; then
    echo -e "${YELLOW}[WARN]${NC} Gagal dari repo chanelog, mencoba apt..."
    apt-get install -y -qq nginx
    return
  fi
  tar -xzf nginx.tar.gz
  cd nginx-1.28.0
  apt-get install -y -qq libpcre3-dev libpcre2-dev zlib1g-dev 2>/dev/null
  ./configure --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib64/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/var/run/nginx.pid \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_realip_module \
    --with-stream \
    --with-stream_ssl_module \
    --with-threads \
    --with-pcre-jit 2>/dev/null
  make -j$(nproc) 2>/dev/null
  make install 2>/dev/null

  # Create systemd service
  cat > /etc/systemd/system/nginx.service <<EOF2
[Unit]
Description=Nginx HTTP Server
After=network.target

[Service]
Type=forking
PIDFile=/var/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t
ExecStart=/usr/sbin/nginx
ExecReload=/bin/kill -s HUP \$MAINPID
ExecStop=/bin/kill -s QUIT \$MAINPID
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF2
  systemctl daemon-reload
  systemctl enable nginx
  echo -e "${GREEN}[OK]${NC} Nginx terinstall"
}

# ─── Install Dropbear ──────────────────────────────────────
install_dropbear() {
  echo -e "\n${CYAN}[*]${NC} Menginstall Dropbear SSH..."
  cd /tmp
  wget -q "$REPO/dropbear-master.zip" -O dropbear.zip
  if [[ $? -ne 0 ]]; then
    apt-get install -y -qq dropbear
  else
    apt-get install -y -qq dropbear
  fi

  # Configure dropbear
  cat > /etc/default/dropbear <<EOF2
NO_START=0
DROPBEAR_PORT=442
DROPBEAR_EXTRA_ARGS="-p 109 -p 143"
DROPBEAR_BANNER="/etc/vpn-script/banner.txt"
DROPBEAR_RECEIVE_WINDOW=65536
EOF2

  systemctl enable dropbear
  systemctl restart dropbear 2>/dev/null || service dropbear restart 2>/dev/null
  echo -e "${GREEN}[OK]${NC} Dropbear terinstall (port: 442, 109, 143)"
}

# ─── Install Xray ──────────────────────────────────────────
install_xray() {
  echo -e "\n${CYAN}[*]${NC} Menginstall Xray dari repository chanelog/bin..."
  mkdir -p /usr/local/bin /etc/xray /var/log/xray

  ARCH=$(uname -m)
  if [[ "$ARCH" == "x86_64" ]]; then
    wget -q "$REPO/Xray-linux-64.zip" -O /tmp/xray.zip
  elif [[ "$ARCH" == "aarch64" ]]; then
    wget -q "$REPO/Xray-linux-arm64-v8a.zip" -O /tmp/xray.zip
  else
    wget -q "$REPO/Xray-linux-64.zip" -O /tmp/xray.zip
  fi

  if [[ $? -ne 0 ]] || [[ ! -f /tmp/xray.zip ]]; then
    echo -e "${YELLOW}[WARN]${NC} Gagal dari repo chanelog, mencoba install-release.sh..."
    wget -q "$REPO/install-release.sh" -O /tmp/install-release.sh
    chmod +x /tmp/install-release.sh
    bash /tmp/install-release.sh 2>/dev/null || {
      # Fallback: download from official GitHub
      XRAY_VER=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep tag_name | cut -d'"' -f4)
      wget -q "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VER}/Xray-linux-64.zip" -O /tmp/xray.zip
      cd /tmp && unzip -q xray.zip
      mv xray /usr/local/bin/xray
    }
  else
    cd /tmp && unzip -q xray.zip
    mv xray /usr/local/bin/xray 2>/dev/null || true
  fi

  chmod +x /usr/local/bin/xray 2>/dev/null

  # Install jq
  if ! command -v jq &>/dev/null; then
    wget -q "$REPO/jq-linux-amd64" -O /usr/local/bin/jq
    chmod +x /usr/local/bin/jq
  fi

  # Create systemd service
  cat > /etc/systemd/system/xray.service <<EOF2
[Unit]
Description=Xray Service
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartSec=3
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF2

  systemctl daemon-reload
  systemctl enable xray
  echo -e "${GREEN}[OK]${NC} Xray terinstall"
}

# ─── Install acme.sh & Request Certificate ─────────────────
install_ssl() {
  local domain="$1"
  echo -e "\n${CYAN}[*]${NC} Menginstall acme.sh dari repository chanelog/bin..."

  mkdir -p /etc/ssl/xray /root/.acme.sh

  wget -q "$REPO/acme.sh" -O /tmp/acme_installer.sh
  if [[ $? -eq 0 ]]; then
    chmod +x /tmp/acme_installer.sh
    bash /tmp/acme_installer.sh --install-online 2>/dev/null || \
    bash /tmp/acme_installer.sh 2>/dev/null
  fi

  # Fallback to official installer
  if [[ ! -f /root/.acme.sh/acme.sh ]]; then
    curl -s https://get.acme.sh | bash -s email=admin@$domain 2>/dev/null
  fi

  # Stop nginx temporarily for standalone
  systemctl stop nginx 2>/dev/null

  echo -e "${CYAN}[*]${NC} Meminta sertifikat SSL untuk ${WHITE}$domain${NC}..."

  /root/.acme.sh/acme.sh --register-account -m "admin@$domain" 2>/dev/null
  /root/.acme.sh/acme.sh --issue --standalone -d "$domain" \
    --keylength ec-256 \
    --httpport 80 2>/dev/null

  if [[ $? -ne 0 ]]; then
    echo -e "${YELLOW}[WARN]${NC} Let's Encrypt gagal, mencoba ZeroSSL..."
    /root/.acme.sh/acme.sh --set-default-ca --server zerossl 2>/dev/null
    /root/.acme.sh/acme.sh --issue --standalone -d "$domain" \
      --keylength ec-256 \
      --httpport 80 2>/dev/null
  fi

  /root/.acme.sh/acme.sh --installcert -d "$domain" \
    --ecc \
    --key-file /etc/ssl/xray/xray.key \
    --fullchain-file /etc/ssl/xray/xray.crt \
    --reloadcmd "systemctl restart xray nginx 2>/dev/null" 2>/dev/null

  chmod 644 /etc/ssl/xray/xray.key
  chmod 644 /etc/ssl/xray/xray.crt

  systemctl start nginx 2>/dev/null
  echo -e "${GREEN}[OK]${NC} SSL Certificate terinstall untuk $domain"
}

# ─── Configure Nginx ───────────────────────────────────────
configure_nginx() {
  local domain="$1"
  mkdir -p /etc/nginx/conf.d /var/www/html

  cat > /etc/nginx/nginx.conf <<EOF2
user www-data;
worker_processes auto;
pid /var/run/nginx.pid;
error_log /var/log/nginx/error.log warn;

events {
    worker_connections 1024;
    multi_accept on;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    include /etc/nginx/conf.d/*.conf;
}
EOF2

  cat > /etc/nginx/conf.d/xray.conf <<EOF2
# Port 80 — non-TLS WebSocket + redirect ke HTTPS untuk request biasa
server {
    listen 80;
    listen [::]:80;
    server_name $domain;

    # VMess WebSocket non-TLS
    location /vmess-ntls {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10003;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    # VLess WebSocket non-TLS
    location /vless-ntls {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10004;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    # Request non-WebSocket redirect ke HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# Port 443 — HTTPS/TLS WebSocket
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $domain;

    ssl_certificate /etc/ssl/xray/xray.crt;
    ssl_certificate_key /etc/ssl/xray/xray.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;

    # VMess WebSocket TLS
    location /vmess-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    # VLess WebSocket TLS
    location /vless-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location / {
        root /var/www/html;
        index index.html;
    }
}
EOF2

  # Default index page
  cat > /var/www/html/index.html <<EOF2
<!DOCTYPE html>
<html><head><title>$domain</title></head>
<body style="background:#1a1a2e;color:#e0e0e0;font-family:monospace;text-align:center;padding:50px">
<h1 style="color:#00d4ff">🛡️ VPN Server</h1>
<p>Protected by acme.sh SSL Certificate</p>
</body></html>
EOF2

  nginx -t 2>/dev/null && systemctl restart nginx 2>/dev/null
  echo -e "${GREEN}[OK]${NC} Nginx dikonfigurasi"
}

# ─── Generate Xray Config ──────────────────────────────────
generate_xray_config() {
  mkdir -p /etc/vpn-script/db
  touch /etc/vpn-script/db/vmess.db
  touch /etc/vpn-script/db/vless.db

  cat > /etc/xray/config.json <<'XRAYEOF'
{
  "log": {
    "loglevel": "warning",
    "error": "/var/log/xray/error.log",
    "access": "/var/log/xray/access.log"
  },
  "inbounds": [
    {
      "tag": "vmess-ws-tls",
      "port": 10001,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vmess-ws",
          "headers": { "Host": "" }
        }
      }
    },
    {
      "tag": "vless-ws-tls",
      "port": 10002,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vless-ws",
          "headers": { "Host": "" }
        }
      }
    },
    {
      "tag": "vmess-ws-ntls",
      "port": 10003,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vmess-ntls",
          "headers": { "Host": "" }
        }
      }
    },
    {
      "tag": "vless-ws-ntls",
      "port": 10004,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vless-ntls",
          "headers": { "Host": "" }
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
XRAYEOF

  echo -e "${GREEN}[OK]${NC} Xray config dibuat"
}

# ─── Copy Script Files ─────────────────────────────────────
install_script_files() {
  local domain="$1"

  mkdir -p $SCRIPT_DIR/db $SCRIPT_DIR/menu

  # Save domain
  echo "$domain" > $SCRIPT_DIR/domain
  echo "$domain" > $SCRIPT_DIR/db/domain

  # Copy all script files from installer directory
  SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  for f in menu.sh lib.sh; do
    if [[ -f "$SELF_DIR/$f" ]]; then
      cp "$SELF_DIR/$f" "$SCRIPT_DIR/"
    fi
  done

  for f in menu/*.sh; do
    if [[ -f "$SELF_DIR/$f" ]]; then
      cp "$SELF_DIR/$f" "$SCRIPT_DIR/menu/"
    fi
  done

  chmod +x $SCRIPT_DIR/*.sh 2>/dev/null
  chmod +x $SCRIPT_DIR/menu/*.sh 2>/dev/null

  # Symlink main menu
  ln -sf $SCRIPT_DIR/menu.sh $BIN_DIR/vpn
  chmod +x $BIN_DIR/vpn

  # Create banner
  cat > $SCRIPT_DIR/banner.txt <<'EOF2'
  ╔══════════════════════════════════════╗
  ║     CHANELOG VPN TUNNEL SERVER       ║
  ║     Unauthorized access prohibited  ║
  ╚══════════════════════════════════════╝
EOF2

  echo -e "${GREEN}[OK]${NC} Script files terinstall"
}

# ─── Configure Cron ────────────────────────────────────────
setup_cron() {
  # Daily cleanup expired accounts
  (crontab -l 2>/dev/null; echo "0 0 * * * /etc/vpn-script/lib.sh delete_expired >> /var/log/vpn-cleanup.log 2>&1") | crontab -
  # Renew SSL
  (crontab -l 2>/dev/null; echo "0 3 * * * /root/.acme.sh/acme.sh --cron >> /var/log/acme-renew.log 2>&1") | crontab -
  echo -e "${GREEN}[OK]${NC} Cron jobs dikonfigurasi"
}

# ─── Firewall ──────────────────────────────────────────────
setup_firewall() {
  # Allow essential ports
  for port in 22 80 443 109 143 442; do
    iptables -I INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null
  done
  # Save rules
  iptables-save > /etc/iptables/rules.v4 2>/dev/null
  echo -e "${GREEN}[OK]${NC} Firewall dikonfigurasi"
}

# ─── Main Installation ─────────────────────────────────────
main() {
  clear
  echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
  echo -e "${WHITE}      CHANELOG VPN SCRIPT - PROSES INSTALASI     ${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
  echo ""

  ask_domain

  DOMAIN=$(cat /tmp/vpn_domain.tmp)

  echo -e "\n${YELLOW}[INFO]${NC} Instalasi akan dimulai untuk domain: ${WHITE}$DOMAIN${NC}"
  echo -ne "  Lanjutkan? [Y/n]: "
  read -r CONFIRM
  [[ "$CONFIRM" =~ ^[Nn]$ ]] && exit 0

  install_deps
  install_nginx
  install_dropbear
  install_xray
  configure_nginx "$DOMAIN"
  generate_xray_config
  install_ssl "$DOMAIN"
  install_script_files "$DOMAIN"
  setup_cron
  setup_firewall

  systemctl restart xray 2>/dev/null
  systemctl restart nginx 2>/dev/null
  systemctl restart dropbear 2>/dev/null

  echo ""
  echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
  echo -e "${WHITE}      ✓  INSTALASI SELESAI!                       ${NC}"
  echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "  Domain  : ${WHITE}$DOMAIN${NC}"
  echo -e "  Jalankan: ${CYAN}vpn${NC}  untuk membuka menu"
  echo ""

  rm -f /tmp/vpn_domain.tmp
  vpn 2>/dev/null || bash $SCRIPT_DIR/menu.sh
}

main "$@"
