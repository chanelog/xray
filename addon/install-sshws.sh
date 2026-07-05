#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - ADDON INSTALLER (ALL-IN-ONE)
#   Fitur: SSH-WS (WebSocket), SSH-WS-TLS, SSH-SSL (Stunnel4)
#   Multi-port: 80, 8880, 8080, 2080, 2082 (nTLS) + 443 (TLS)
#   Bersifat ADITIF: tidak menghapus/mengganti konfigurasi
#   Nginx/Xray/Dropbear yang sudah berjalan.
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}[ERROR]${NC} Jalankan sebagai root!"
  exit 1
fi

DOMAIN=$(get_domain)

echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "${WHITE}   INSTALL ADDON: SSH-WS / SSH-WS-TLS / SSH-SSL   ${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"

# ─── 1. Dependensi ─────────────────────────────────────────
echo -e "\n${CYAN}[*]${NC} Menginstall dependensi (python3, stunnel4)..."
apt-get update -qq 2>/dev/null
apt-get install -y -qq python3 stunnel4 2>/dev/null
echo -e "${GREEN}[OK]${NC} Dependensi terinstall"

# ─── 2. Buat direktori DB SSH bila belum ada ───────────────
mkdir -p "$DB_DIR"
touch "$DB_SSH"

# ─── 3. Deploy ws-proxy (SSH-WS): relay WebSocket -> Dropbear
echo -e "\n${CYAN}[*]${NC} Memasang ws-proxy (SSH over WebSocket)..."

cat > /usr/local/bin/ws-proxy.py <<'PYEOF'
#!/usr/bin/env python3
"""
ws-proxy: proxy universal untuk SSH-WS & SSH-SSL.
Membaca request pembuka dari client (bisa berupa WebSocket Upgrade,
maupun HTTP CONNECT dari client seperti HTTP Custom tab "SSH"+SSL),
membalas dengan response yang sesuai, lalu meneruskan byte mentah SSH
ke server SSH lokal (dropbear/openssh) yang sudah berjalan.
Hanya mendengarkan di 127.0.0.1 - diakses lewat Nginx (SSH-WS) atau
lewat Stunnel (SSH-SSL).
"""
import asyncio
import os

LISTEN_HOST = "127.0.0.1"
LISTEN_PORT = int(os.environ.get("WS_PROXY_PORT", "700"))
BACKEND_HOST = "127.0.0.1"
BACKEND_PORT = int(os.environ.get("SSH_BACKEND_PORT", "143"))

WS_RESPONSE = (
    b"HTTP/1.1 101 Switching Protocols\r\n"
    b"Upgrade: websocket\r\n"
    b"Connection: Upgrade\r\n\r\n"
)
CONNECT_RESPONSE = b"HTTP/1.1 200 Connection Established\r\n\r\n"


async def pipe(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    try:
        while True:
            data = await reader.read(8192)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    except (ConnectionResetError, BrokenPipeError):
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    try:
        is_websocket = False
        try:
            while True:
                line = await asyncio.wait_for(reader.readline(), timeout=10)
                if line in (b"\r\n", b""):
                    break
                if b"upgrade" in line.lower() and b"websocket" in line.lower():
                    is_websocket = True
        except asyncio.TimeoutError:
            pass

        writer.write(WS_RESPONSE if is_websocket else CONNECT_RESPONSE)
        await writer.drain()

        backend_reader, backend_writer = await asyncio.open_connection(
            BACKEND_HOST, BACKEND_PORT
        )

        await asyncio.gather(
            pipe(reader, backend_writer),
            pipe(backend_reader, writer),
        )
    except Exception:
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def main():
    server = await asyncio.start_server(handle_client, LISTEN_HOST, LISTEN_PORT)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
PYEOF

chmod +x /usr/local/bin/ws-proxy.py

cat > /etc/systemd/system/ws-proxy.service <<EOF2
[Unit]
Description=SSH-WS / SSH-SSL Universal Proxy (to Dropbear)
After=network.target dropbear.service

[Service]
Environment=WS_PROXY_PORT=$WS_PROXY_PORT
Environment=SSH_BACKEND_PORT=$SSH_BACKEND_PORT
ExecStart=/usr/bin/python3 /usr/local/bin/ws-proxy.py
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF2

systemctl daemon-reload
systemctl enable ws-proxy 2>/dev/null
systemctl restart ws-proxy 2>/dev/null
echo -e "${GREEN}[OK]${NC} ws-proxy aktif di 127.0.0.1:$WS_PROXY_PORT → 127.0.0.1:$SSH_BACKEND_PORT"

# ─── 4. Setup Nginx untuk SSH-WS (semua port) ──────────────
NGINX_CONF="/etc/nginx/conf.d/xray.conf"
if [[ -f "$NGINX_CONF" ]]; then
  echo -e "\n${CYAN}[*]${NC} Memeriksa konfigurasi Nginx untuk SSH-WS..."

  # Cek apakah location /ssh-ws sudah ada di semua server block
  if grep -q "location /ssh-ws" "$NGINX_CONF"; then
    echo -e "${YELLOW}[SKIP]${NC} Location /ssh-ws sudah ada di Nginx"
  else
    echo -e "${YELLOW}[WARN]${NC} Location /ssh-ws belum ditemukan di Nginx!"
    echo -e "${YELLOW}[INFO]${NC} Pastikan install.sh sudah dijalankan dengan versi terbaru."
    echo -e "${YELLOW}[INFO]${NC} Atau tambahkan manual location /ssh-ws ke setiap server block."
  fi
else
  echo -e "${YELLOW}[WARN]${NC} $NGINX_CONF tidak ditemukan!"
fi

# ─── 5. Setup Stunnel4 untuk SSH-SSL ────────────────────────
echo -e "\n${CYAN}[*]${NC} Mengkonfigurasi Stunnel4 (SSH-SSL)..."

if [[ -f /etc/ssl/xray/xray.crt && -f /etc/ssl/xray/xray.key ]]; then
  cat /etc/ssl/xray/xray.crt /etc/ssl/xray/xray.key > /etc/stunnel/stunnel.pem 2>/dev/null
else
  echo -e "${YELLOW}[WARN]${NC} Sertifikat Xray tidak ditemukan, membuat self-signed untuk stunnel..."
  openssl req -x509 -newkey rsa:2048 -keyout /tmp/stunnel.key -out /tmp/stunnel.crt \
    -days 365 -nodes -subj "/CN=${DOMAIN:-localhost}" 2>/dev/null
  cat /tmp/stunnel.crt /tmp/stunnel.key > /etc/stunnel/stunnel.pem
  rm -f /tmp/stunnel.key /tmp/stunnel.crt
fi
chmod 600 /etc/stunnel/stunnel.pem

if grep -q "\[ssh-ssl\]" /etc/stunnel/stunnel.conf 2>/dev/null; then
  echo -e "${YELLOW}[UPDATE]${NC} Block [ssh-ssl] sudah ada, memperbarui..."
  awk '
    /^\[ssh-ssl\]/ { skip=1; next }
    /^\[/ && skip { skip=0 }
    !skip { print }
  ' /etc/stunnel/stunnel.conf > /tmp/stunnel.conf.new
  cp /tmp/stunnel.conf.new /etc/stunnel/stunnel.conf
  rm -f /tmp/stunnel.conf.new
fi

cat >> /etc/stunnel/stunnel.conf <<EOF2

[ssh-ssl]
accept = $STUNNEL_SSL_PORT
connect = 127.0.0.1:$WS_PROXY_PORT
cert = /etc/stunnel/stunnel.pem
EOF2

sed -i 's/^ENABLED=0/ENABLED=1/' /etc/default/stunnel4 2>/dev/null
grep -q "^ENABLED=" /etc/default/stunnel4 2>/dev/null || echo "ENABLED=1" >> /etc/default/stunnel4

systemctl enable stunnel4 2>/dev/null
systemctl restart stunnel4 2>/dev/null
echo -e "${GREEN}[OK]${NC} Stunnel4 aktif di port $STUNNEL_SSL_PORT → 127.0.0.1:$SSH_BACKEND_PORT"

# ─── 6. Firewall (aditif, tidak menutup port lain) ─────────
echo -e "\n${CYAN}[*]${NC} Membuka port firewall untuk fitur baru..."
iptables -I INPUT -p tcp --dport "$STUNNEL_SSL_PORT" -j ACCEPT 2>/dev/null
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4 2>/dev/null
echo -e "${GREEN}[OK]${NC} Port $STUNNEL_SSL_PORT dibuka"

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "${WHITE}   ✓  ADDON SSH-WS / SSH-SSL BERHASIL DIINSTALL   ${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "  SSH-WS (nTLS) : port 80   path /ssh-ws        (nginx → ws-proxy)"
echo -e "  SSH-WS (nTLS) : port 8880 path /ssh-ws        (nginx → ws-proxy)"
echo -e "  SSH-WS (nTLS) : port 8080 path /ssh-ws        (nginx → ws-proxy)"
echo -e "  SSH-WS (nTLS) : port 2080 path /ssh-ws        (nginx → ws-proxy)"
echo -e "  SSH-WS (nTLS) : port 2082 path /ssh-ws        (nginx → ws-proxy)"
echo -e "  SSH-WS (TLS)  : port 443  path /ssh-ws        (nginx → ws-proxy)"
echo -e "  SSH-SSL       : port $STUNNEL_SSL_PORT (stunnel4 → ws-proxy)"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
