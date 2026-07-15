#!/bin/bash
#====================================================
# Script Auto-Install: SSH WebSocket + Xray
# SSL: acme.sh (bukan Certbot)
#====================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

DOMAIN=""
EMAIL=""

banner() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}SSH WebSocket + Xray Auto Installer${NC}          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}       ${YELLOW}SSL: acme.sh | Domain Mode${NC}             ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════╝${NC}"
    echo ""
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[ERROR]${NC} Script harus dijalankan sebagai root!"
        exit 1
    fi
}

input_domain() {
    echo -e "${YELLOW}[SETUP]${NC} Konfigurasi Domain"
    echo "─────────────────────────────────────────────────"
    while true; do
        read -p "Masukkan domain (contoh: vpn.example.com): " DOMAIN
        if [[ -n "$DOMAIN" ]]; then break
        else echo -e "${RED}[ERROR]${NC} Domain tidak boleh kosong!"
        fi
    done
    read -p "Masukkan email untuk SSL (default: admin@$DOMAIN): " EMAIL
    EMAIL=${EMAIL:-admin@$DOMAIN}
    echo -e "${GREEN}[INFO]${NC} Domain: $DOMAIN | Email: $EMAIL"
    echo ""
}

update_system() {
    echo -e "${YELLOW}[PROSES]${NC} Updating system..."
    apt-get update -y
    apt-get upgrade -y
    apt-get install -y curl wget git nano unzip zip net-tools cron screen htop         nginx jq qrencode uuid-runtime socat netcat-openbsd         libnss3-tools python3
    echo -e "${GREEN}[OK]${NC} System updated!"
}

# ============================================================
# INSTALL acme.sh (bukan Certbot)
# ============================================================
install_acme() {
    echo -e "${YELLOW}[PROSES]${NC} Installing acme.sh..."

    # Install acme.sh
    curl https://get.acme.sh | sh -s email=$EMAIL

    # Source acme.sh
    export HOME=/root
    [[ -f "$HOME/.acme.sh/acme.sh" ]] && source "$HOME/.acme.sh/acme.sh.env" 2>/dev/null || true

    # Set default CA ke Let's Encrypt
    "$HOME/.acme.sh/acme.sh" --set-default-ca --server letsencrypt

    echo -e "${GREEN}[OK]${NC} acme.sh installed!"
}

# ============================================================
# GENERATE SSL dengan acme.sh (Standalone mode)
# ============================================================
setup_ssl_acme() {
    echo -e "${YELLOW}[PROSES]${NC} Generate SSL Certificate dengan acme.sh..."

    # Stop nginx dulu biar port 80 free
    systemctl stop nginx 2>/dev/null || true

    # Issue cert pakai standalone mode (port 80)
    "$HOME/.acme.sh/acme.sh" --issue -d $DOMAIN --standalone --force

    # Install cert ke path standar
    mkdir -p /etc/letsencrypt/live/$DOMAIN
    "$HOME/.acme.sh/acme.sh" --install-cert -d $DOMAIN         --cert-file /etc/letsencrypt/live/$DOMAIN/cert.pem         --key-file /etc/letsencrypt/live/$DOMAIN/privkey.pem         --fullchain-file /etc/letsencrypt/live/$DOMAIN/fullchain.pem         --reloadcmd "systemctl reload nginx; systemctl restart xray"

    # Auto renew cron sudah di-setup oleh acme.sh

    systemctl start nginx
    echo -e "${GREEN}[OK]${NC} SSL Certificate berhasil dibuat dengan acme.sh!"
}

# ============================================================
# INSTALL Dropbear (PERLU - untuk SSH alternatif)
# ============================================================
install_dropbear() {
    echo -e "${YELLOW}[PROSES]${NC} Installing Dropbear..."
    apt-get install -y dropbear

    cat > /etc/default/dropbear << 'EOF'
NO_START=0
DROPBEAR_PORT=109
DROPBEAR_EXTRA_ARGS="-p 777"
DROPBEAR_BANNER="/etc/banner"
DROPBEAR_RECEIVE_WINDOW=65536
EOF

    cat > /etc/banner << 'EOF'
╔═══════════════════════════════════════╗
║   SSH WebSocket + Xray Server         ║
║   No Spam | No DDoS | No Torrent      ║
╚═══════════════════════════════════════╝
EOF

    systemctl restart dropbear
    systemctl enable dropbear
    echo -e "${GREEN}[OK]${NC} Dropbear installed (Port 109, SSL 777)"
}

# ============================================================
# INSTALL Stunnel4 (OPSIONAL - tapi direkomendasikan)
# ============================================================
install_stunnel() {
    echo -e "${YELLOW}[PROSES]${NC} Installing Stunnel4..."
    apt-get install -y stunnel4

    # Enable stunnel
    sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/stunnel4 2>/dev/null || echo "ENABLED=1" > /etc/default/stunnel4

    # Config stunnel - wrap Dropbear dengan SSL
    cat > /etc/stunnel/stunnel.conf << EOF
pid = /var/run/stunnel4.pid
cert = /etc/letsencrypt/live/$DOMAIN/fullchain.pem
key = /etc/letsencrypt/live/$DOMAIN/privkey.pem
client = no
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

[dropbear]
accept = 444
connect = 127.0.0.1:109

[openssh]
accept = 445
connect = 127.0.0.1:22
EOF

    systemctl restart stunnel4
    systemctl enable stunnel4
    echo -e "${GREEN}[OK]${NC} Stunnel4 installed (Port 444 SSL, 445 SSL)"
}

# ============================================================
# INSTALL HAProxy (OPSIONAL - untuk load balancing/multi-port)
# ============================================================
install_haproxy() {
    echo -e "${YELLOW}[PROSES]${NC} Installing HAProxy..."
    apt-get install -y haproxy

    cat > /etc/haproxy/haproxy.cfg << EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log global
    mode tcp
    option tcplog
    option dontlognull
    timeout connect 5000
    timeout client 50000
    timeout server 50000

# Frontend SSHWS (WebSocket via HTTP)
frontend sshws_frontend
    bind *:8080
    mode http
    option httpchk
    acl is_websocket hdr_beg(Host) -i ws
    acl is_upgrade hdr_beg(Upgrade) -i websocket
    use_backend sshws_backend if is_websocket is_upgrade
    default_backend nginx_backend

backend sshws_backend
    mode http
    server sshws_local 127.0.0.1:7001 check

backend nginx_backend
    mode http
    server nginx_local 127.0.0.1:80 check

# Frontend Xray TCP
frontend xray_tcp
    bind *:8443 ssl crt /etc/letsencrypt/live/$DOMAIN/fullchain.pem
    mode tcp
    default_backend xray_backend

backend xray_backend
    mode tcp
    server xray_local 127.0.0.1:8444 check
EOF

    systemctl restart haproxy
    systemctl enable haproxy
    echo -e "${GREEN}[OK]${NC} HAProxy installed (Port 8080, 8443)"
}

install_badvpn() {
    echo -e "${YELLOW}[PROSES]${NC} Installing BadVPN UDPGW..."
    apt-get install -y cmake make gcc
    cd /tmp
    wget -q https://github.com/ambrop72/badvpn/archive/refs/tags/1.999.130.tar.gz -O badvpn.tar.gz
    tar -xzf badvpn.tar.gz
    cd badvpn-1.999.130
    cmake -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 . >/dev/null 2>&1
    make >/dev/null 2>&1
    cp udpgw/badvpn-udpgw /usr/bin/
    cd /
    rm -rf /tmp/badvpn*

    cat > /etc/systemd/system/badvpn.service << 'EOF'
[Unit]
Description=BadVPN UDP Gateway
After=network.target
[Service]
Type=simple
User=root
ExecStart=/usr/bin/badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 1000 --max-connections-for-client 100
Restart=always
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable badvpn
    systemctl start badvpn
    echo -e "${GREEN}[OK]${NC} BadVPN UDPGW installed (Port 7300)"
}

install_xray() {
    echo -e "${YELLOW}[PROSES]${NC} Installing Xray Core..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

    UUID_VLESS=$(cat /proc/sys/kernel/random/uuid)
    UUID_VMESS=$(cat /proc/sys/kernel/random/uuid)
    UUID_TROJAN=$(openssl rand -hex 16)

    mkdir -p /usr/local/etc/xray
    cat > /usr/local/etc/xray/uuids.txt << EOF
VLESS: $UUID_VLESS
VMESS: $UUID_VMESS
TROJAN: $UUID_TROJAN
EOF
    echo -e "${GREEN}[OK]${NC} Xray Core installed!"
}

config_xray() {
    echo -e "${YELLOW}[PROSES]${NC} Configuring Xray..."

    CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

    UUID_VLESS=$(grep "VLESS:" /usr/local/etc/xray/uuids.txt | awk '{print $2}')
    UUID_VMESS=$(grep "VMESS:" /usr/local/etc/xray/uuids.txt | awk '{print $2}')
    UUID_TROJAN=$(grep "TROJAN:" /usr/local/etc/xray/uuids.txt | awk '{print $2}')

    cat > /usr/local/etc/xray/config.json << EOF
{
  "log": {"access": "/var/log/xray/access.log", "error": "/var/log/xray/error.log", "loglevel": "warning"},
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$UUID_VLESS", "flow": "xtls-rprx-vision", "level": 0, "email": "vless@$DOMAIN"}],
        "decryption": "none",
        "fallbacks": [{"dest": 80}]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [{"certificateFile": "$CERT", "keyFile": "$KEY"}],
          "alpn": ["h2", "http/1.1"]
        }
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"]}
    },
    {
      "port": 8443,
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$UUID_VLESS", "level": 0, "email": "vless-ws@$DOMAIN"}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {"certificates": [{"certificateFile": "$CERT", "keyFile": "$KEY"}]},
        "wsSettings": {"path": "/vless-ws", "headers": {"Host": "$DOMAIN"}}
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"]}
    },
    {
      "port": 8443,
      "protocol": "vmess",
      "settings": {
        "clients": [{"id": "$UUID_VMESS", "alterId": 0, "level": 0, "email": "vmess@$DOMAIN"}]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {"certificates": [{"certificateFile": "$CERT", "keyFile": "$KEY"}]},
        "wsSettings": {"path": "/vmess-ws", "headers": {"Host": "$DOMAIN"}}
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"]}
    },
    {
      "port": 8443,
      "protocol": "trojan",
      "settings": {
        "clients": [{"password": "$UUID_TROJAN", "level": 0, "email": "trojan@$DOMAIN"}],
        "fallbacks": [{"dest": 80}]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {"certificates": [{"certificateFile": "$CERT", "keyFile": "$KEY"}]},
        "wsSettings": {"path": "/trojan-ws", "headers": {"Host": "$DOMAIN"}}
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"]}
    }
  ],
  "outbounds": [
    {"protocol": "freedom", "settings": {}},
    {"protocol": "blackhole", "settings": {}, "tag": "blocked"}
  ],
  "routing": {
    "rules": [{"type": "field", "ip": ["geoip:private"], "outboundTag": "blocked"}]
  }
}
EOF

    mkdir -p /var/log/xray
    touch /var/log/xray/access.log /var/log/xray/error.log
    systemctl restart xray
    systemctl enable xray
    echo -e "${GREEN}[OK]${NC} Xray configured!"
}

config_nginx() {
    echo -e "${YELLOW}[PROSES]${NC} Configuring Nginx..."
    rm -f /etc/nginx/sites-enabled/default

    cat > /etc/nginx/sites-available/sshws << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate $CERT;
    ssl_certificate_key $KEY;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    location /ssh-ws {
        proxy_pass http://127.0.0.1:7001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 86400;
    }

    location /vless-ws {
        proxy_pass http://127.0.0.1:8443;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400;
    }

    location /vmess-ws {
        proxy_pass http://127.0.0.1:8443;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400;
    }

    location /trojan-ws {
        proxy_pass http://127.0.0.1:8443;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400;
    }

    location / {
        root /var/www/html;
        index index.html;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/sshws /etc/nginx/sites-enabled/sshws
    mkdir -p /var/www/html
    cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html><html><head><title>Server Active</title>
<style>body{font-family:Arial,sans-serif;text-align:center;padding:50px;background:#1a1a2e;color:#eee;}h1{color:#00d4ff;}</style>
</head><body><h1>✅ Server Active</h1><p>SSH WebSocket + Xray Server</p></body></html>
EOF

    nginx -t && systemctl restart nginx
    systemctl enable nginx
    echo -e "${GREEN}[OK]${NC} Nginx configured!"
}

install_sshws() {
    echo -e "${YELLOW}[PROSES]${NC} Installing SSH WebSocket Server..."
    apt-get install -y python3 python3-pip

    cat > /usr/local/bin/sshws-server.py << 'PYEOF'
#!/usr/bin/env python3
import socket, threading
LOCAL_HOST, LOCAL_PORT = '127.0.0.1', 7001
SSH_HOST, SSH_PORT = '127.0.0.1', 22
BUFFER_SIZE = 4096

def handle_client(client_socket):
    try:
        ssh_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        ssh_socket.connect((SSH_HOST, SSH_PORT))
        def forward(source, destination):
            while True:
                try:
                    data = source.recv(BUFFER_SIZE)
                    if not data: break
                    destination.send(data)
                except: break
            source.close(); destination.close()
        t1 = threading.Thread(target=forward, args=(client_socket, ssh_socket))
        t2 = threading.Thread(target=forward, args=(ssh_socket, client_socket))
        t1.start(); t2.start()
        t1.join(); t2.join()
    except Exception as e:
        client_socket.close()

def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((LOCAL_HOST, LOCAL_PORT))
    server.listen(100)
    print(f"[*] SSH WebSocket listening on {LOCAL_HOST}:{LOCAL_PORT}")
    while True:
        client, addr = server.accept()
        thread = threading.Thread(target=handle_client, args=(client,))
        thread.start()
if __name__ == '__main__': main()
PYEOF
    chmod +x /usr/local/bin/sshws-server.py

    cat > /etc/systemd/system/sshws.service << 'EOF'
[Unit]
Description=SSH WebSocket Server
After=network.target
[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/sshws-server.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable sshws
    systemctl start sshws
    echo -e "${GREEN}[OK]${NC} SSHWS installed (Port 7001 via Nginx 443)"
}

install_menu() {
    echo -e "${YELLOW}[PROSES]${NC} Installing Menu..."

    cat > /usr/local/bin/sshws-menu << 'MENUEOF'
#!/bin/bash
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
clear
echo -e "${CYAN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}     ${GREEN}SSH WebSocket + Xray Management${NC}          ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}[SERVER INFO]${NC}"
echo "─────────────────────────────────────────────────"
echo -e "Hostname : $(hostname)"
echo -e "IP       : $(curl -s ifconfig.me 2>/dev/null || echo 'N/A')"
echo -e "Domain   : $(cat /usr/local/etc/xray/domain.txt 2>/dev/null || echo 'N/A')"
echo ""
echo -e "${YELLOW}[SERVICE STATUS]${NC}"
echo "─────────────────────────────────────────────────"
echo -e "SSH          : $(systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null || echo 'N/A')"
echo -e "Dropbear     : $(systemctl is-active dropbear 2>/dev/null || echo 'N/A')"
echo -e "Stunnel4     : $(systemctl is-active stunnel4 2>/dev/null || echo 'N/A')"
echo -e "Nginx        : $(systemctl is-active nginx 2>/dev/null || echo 'N/A')"
echo -e "Xray         : $(systemctl is-active xray 2>/dev/null || echo 'N/A')"
echo -e "SSHWS        : $(systemctl is-active sshws 2>/dev/null || echo 'N/A')"
echo -e "BadVPN       : $(systemctl is-active badvpn 2>/dev/null || echo 'N/A')"
echo ""
echo -e "${YELLOW}[PORTS]${NC}"
echo "─────────────────────────────────────────────────"
echo -e "SSH          : 22"
echo -e "Dropbear     : 109"
echo -e "Dropbear SSL : 777"
echo -e "Stunnel SSL  : 444 (Dropbear) | 445 (OpenSSH)"
echo -e "SSHWS        : 443 (via Nginx WebSocket)"
echo -e "Xray VLESS   : 443 (TCP) | 8443 (WS via Nginx 443)"
echo -e "Xray VMESS   : 8443 (WS via Nginx 443)"
echo -e "Xray Trojan  : 8443 (WS via Nginx 443)"
echo -e "BadVPN UDPGW : 7300"
echo ""
echo -e "${YELLOW}[XRAY UUIDs]${NC}"
echo "─────────────────────────────────────────────────"
cat /usr/local/etc/xray/uuids.txt 2>/dev/null || echo "N/A"
echo ""
echo -e "${YELLOW}[COMMANDS]${NC}"
echo "─────────────────────────────────────────────────"
echo -e "${GREEN}sshws-menu${NC}    : Menu ini"
echo -e "${GREEN}add-user${NC}      : Tambah user SSH"
echo -e "${GREEN}del-user${NC}      : Hapus user SSH"
echo -e "${GREEN}list-user${NC}     : List user SSH"
echo -e "${GREEN}restart-xray${NC}  : Restart Xray"
echo -e "${GREEN}restart-sshws${NC} : Restart SSHWS"
echo -e "${GREEN}restart-all${NC}   : Restart semua service"
echo ""
MENUEOF
    chmod +x /usr/local/bin/sshws-menu

    cat > /usr/local/bin/add-user << 'ADDEOF'
#!/bin/bash
read -p "Username: " user
read -s -p "Password: " pass; echo ""
read -p "Expired (hari): " exp
useradd -e $(date -d "+$exp days" +%Y-%m-%d) -s /bin/false -M $user
echo "$user:$pass" | chpasswd
echo ""
echo "✅ User berhasil dibuat!"
echo "─────────────────────────────"
echo "Username : $user"
echo "Password : $pass"
echo "Expired  : $(date -d "+$exp days" +%Y-%m-%d)"
echo "─────────────────────────────"
ADDEOF
    chmod +x /usr/local/bin/add-user

    cat > /usr/local/bin/del-user << 'DELEOF'
#!/bin/bash
read -p "Username yang akan dihapus: " user
userdel -f $user 2>/dev/null
echo "✅ User $user berhasil dihapus!"
DELEOF
    chmod +x /usr/local/bin/del-user

    cat > /usr/local/bin/list-user << 'LISTEOF'
#!/bin/bash
echo "═══════════════════════════════════════"
echo "         DAFTAR USER SSH"
echo "═══════════════════════════════════════"
echo "Username          | Expired"
echo "───────────────────────────────────────"
while IFS=: read -r username _ uid _ _ home shell; do
    if [[ "$uid" -ge 1000 && "$uid" != 65534 && "$shell" == "/bin/false" ]]; then
        exp=$(chage -l "$username" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs)
        printf "%-18s | %s\n" "$username" "$exp"
    fi
done < /etc/passwd
echo "═══════════════════════════════════════"
LISTEOF
    chmod +x /usr/local/bin/list-user

    cat > /usr/local/bin/restart-xray << 'REXEOF'
#!/bin/bash
systemctl restart xray
echo "✅ Xray restarted!"
REXEOF
    chmod +x /usr/local/bin/restart-xray

    cat > /usr/local/bin/restart-sshws << 'RSEOF'
#!/bin/bash
systemctl restart sshws
echo "✅ SSHWS restarted!"
RSEOF
    chmod +x /usr/local/bin/restart-sshws

    cat > /usr/local/bin/restart-all << 'RAEOF'
#!/bin/bash
systemctl restart xray sshws nginx dropbear stunnel4 badvpn
echo "✅ Semua service restarted!"
RAEOF
    chmod +x /usr/local/bin/restart-all

    echo "$DOMAIN" > /usr/local/etc/xray/domain.txt
    echo -e "${GREEN}[OK]${NC} Menu installed!"
}

enable_bbr() {
    echo -e "${YELLOW}[PROSES]${NC} Enabling BBR..."
    cat >> /etc/sysctl.conf << 'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    sysctl -p >/dev/null 2>&1
    echo -e "${GREEN}[OK]${NC} BBR enabled!"
}

show_info() {
    clear
    UUID_VLESS=$(grep "VLESS:" /usr/local/etc/xray/uuids.txt 2>/dev/null | awk '{print $2}')
    UUID_VMESS=$(grep "VMESS:" /usr/local/etc/xray/uuids.txt 2>/dev/null | awk '{print $2}')
    UUID_TROJAN=$(grep "TROJAN:" /usr/local/etc/xray/uuids.txt 2>/dev/null | awk '{print $2}')

    echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}     ✅ ${CYAN}INSTALLASI SELESAI!${NC}                    ${GREEN}║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}📡 INFORMASI SERVER${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "Domain       : ${GREEN}$DOMAIN${NC}"
    echo -e "IP Server    : ${GREEN}$(curl -s ifconfig.me)${NC}"
    echo -e "Email SSL    : ${GREEN}$EMAIL${NC}"
    echo -e "SSL Tool     : ${GREEN}acme.sh${NC}"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}🔌 PORTS${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "SSH          : ${GREEN}22${NC}"
    echo -e "Dropbear     : ${GREEN}109${NC}"
    echo -e "Dropbear SSL : ${GREEN}777${NC} (Dropbear native)"
    echo -e "Stunnel SSL  : ${GREEN}444${NC} (Dropbear via Stunnel) | ${GREEN}445${NC} (OpenSSH via Stunnel)"
    echo -e "SSHWS        : ${GREEN}443${NC} (via Nginx WebSocket)"
    echo -e "Xray VLESS   : ${GREEN}443${NC} (TCP) | ${GREEN}8443${NC} (WS via Nginx 443)"
    echo -e "Xray VMESS   : ${GREEN}8443${NC} (WS via Nginx 443)"
    echo -e "Xray Trojan  : ${GREEN}8443${NC} (WS via Nginx 443)"
    echo -e "BadVPN UDPGW : ${GREEN}7300${NC}"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}🔑 XRAY UUIDs${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "VLESS : ${GREEN}$UUID_VLESS${NC}"
    echo -e "VMESS : ${GREEN}$UUID_VMESS${NC}"
    echo -e "TROJAN: ${GREEN}$UUID_TROJAN${NC}"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}📱 SSH WebSocket Payload${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}GET /ssh-ws HTTP/1.1${NC}"
    echo -e "${GREEN}Host: $DOMAIN${NC}"
    echo -e "${GREEN}Upgrade: websocket${NC}"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}📱 Xray VLESS WS URI${NC}"
    echo -e "${GREEN}vless://$UUID_VLESS@$DOMAIN:443?type=ws&security=tls&path=/vless-ws&host=$DOMAIN#VLESS-WS${NC}"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}📱 Xray VMESS WS URI${NC}"
    echo -e "${GREEN}vmess://$(echo '{"v":"2","ps":"VMESS-WS","add":"'$DOMAIN'","port":"443","id":"'$UUID_VMESS'","aid":"0","scy":"auto","net":"ws","type":"none","host":"'$DOMAIN'","path":"/vmess-ws","tls":"tls"}' | base64 -w 0)${NC}"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}📱 Xray Trojan WS URI${NC}"
    echo -e "${GREEN}trojan://$UUID_TROJAN@$DOMAIN:443?type=ws&security=tls&path=/trojan-ws&host=$DOMAIN#TROJAN-WS${NC}"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}🛠️  COMMANDS${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}sshws-menu${NC}    : Menu"
    echo -e "${GREEN}add-user${NC}      : Tambah user"
    echo -e "${GREEN}del-user${NC}      : Hapus user"
    echo -e "${GREEN}list-user${NC}     : List user"
    echo -e "${GREEN}restart-xray${NC}  : Restart Xray"
    echo -e "${GREEN}restart-sshws${NC} : Restart SSHWS"
    echo -e "${GREEN}restart-all${NC}   : Restart semua service"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✅ Server siap digunakan!${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
}

main() {
    banner
    check_root
    input_domain
    update_system
    install_acme
    setup_ssl_acme
    install_dropbear
    install_stunnel
    install_badvpn
    install_xray
    config_xray
    config_nginx
    install_sshws
    install_menu
    enable_bbr
    show_info
}

main
