#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - SSH WS SETUP
#   Dipanggil dari install.sh
# ============================================================

SCRIPT_DIR="/etc/vpn-script"

setup_ssh_ws() {
  local domain="$1"

  echo -e "\n\033[0;36m[*]\033[0m Setting up SSH WebSocket..."

  # ── Install websocket proxy (python3) ───────────────────
  apt-get install -y -qq python3 python3-pip screen 2>/dev/null

  # Buat script SSH WS proxy (port 80, 8080, 8081-9999 → ssh port 22)
  cat > /usr/local/bin/ssh-ws << 'PYEOF'
#!/usr/bin/env python3
# SSH WebSocket Proxy
import socket, threading, select, sys

LISTEN_PORTS = [80, 8080]
SSH_PORT = 22
BUFFER = 4096
RESPONSE = b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"

def handle(client):
    try:
        data = client.recv(BUFFER)
        if not data:
            client.close()
            return
        # Send WebSocket handshake response
        client.send(RESPONSE)
        # Connect to SSH
        ssh = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        ssh.connect(('127.0.0.1', SSH_PORT))
        # Bridge
        def bridge(src, dst):
            try:
                while True:
                    r, _, _ = select.select([src], [], [], 60)
                    if r:
                        d = src.recv(BUFFER)
                        if not d: break
                        dst.send(d)
            except: pass
            finally:
                try: src.close()
                except: pass
                try: dst.close()
                except: pass
        threading.Thread(target=bridge, args=(client, ssh), daemon=True).start()
        threading.Thread(target=bridge, args=(ssh, client), daemon=True).start()
    except Exception as e:
        try: client.close()
        except: pass

def listen(port):
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        srv.bind(('0.0.0.0', port))
        srv.listen(100)
        print(f"[SSH-WS] Listening on port {port}")
        while True:
            client, _ = srv.accept()
            threading.Thread(target=handle, args=(client,), daemon=True).start()
    except Exception as e:
        print(f"[SSH-WS] Port {port} error: {e}")

if __name__ == '__main__':
    ports = [int(p) for p in sys.argv[1:]] if len(sys.argv) > 1 else LISTEN_PORTS
    threads = []
    for p in ports:
        t = threading.Thread(target=listen, args=(p,), daemon=True)
        t.start()
        threads.append(t)
    for t in threads:
        t.join()
PYEOF
  chmod +x /usr/local/bin/ssh-ws

  # Systemd service SSH WS
  cat > /etc/systemd/system/ssh-ws.service << 'EOF2'
[Unit]
Description=SSH WebSocket Proxy
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/ssh-ws 80 8080
Restart=always
RestartSec=3
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF2

  systemctl daemon-reload
  systemctl enable ssh-ws
  systemctl restart ssh-ws

  echo -e "\033[0;32m[OK]\033[0m SSH WS service running (port 80, 8080)"

  # ── Nginx: SSH WS via port 80 & SSL WS via 443 ─────────
  # Tambah location /ssh-ws di nginx (port 80 & 443)
  # Port 80 block
  sed -i '/location \/ {/i\
    # SSH WebSocket\
    location /ssh-ws {\
        proxy_redirect off;\
        proxy_pass http://127.0.0.1:2082;\
        proxy_http_version 1.1;\
        proxy_set_header Upgrade $http_upgrade;\
        proxy_set_header Connection "upgrade";\
        proxy_set_header Host $host;\
        proxy_set_header X-Real-IP $remote_addr;\
        proxy_connect_timeout 60s;\
        proxy_read_timeout 3600s;\
    }\
' /etc/nginx/conf.d/xray.conf 2>/dev/null

  # ── SSH WS internal proxy port 2082 → SSH 22 ────────────
  # Update ssh-ws service untuk listen di 2082 (nginx proxy ke sini)
  cat > /etc/systemd/system/ssh-ws.service << 'EOF2'
[Unit]
Description=SSH WebSocket Proxy
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/ssh-ws 2082 8080
Restart=always
RestartSec=3
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF2

  systemctl daemon-reload
  systemctl restart ssh-ws

  # ── SSH SSL/TLS via stunnel (port 400-900) ───────────────
  apt-get install -y -qq stunnel4 2>/dev/null

  cat > /etc/stunnel/stunnel.conf << EOF2
; Stunnel SSL/TLS Wrapper untuk SSH
pid = /var/run/stunnel4/stunnel.pid
output = /var/log/stunnel4/stunnel.log

; SSH SSL/TLS port 443 (SSL WS)
[ssh-ssl-443]
accept  = 0.0.0.0:777
connect = 127.0.0.1:22
cert    = /etc/ssl/xray/xray.crt
key     = /etc/ssl/xray/xray.key

; SSH SSL/TLS port range (400-900 sample ports)
[ssh-ssl-400]
accept  = 0.0.0.0:400
connect = 127.0.0.1:22
cert    = /etc/ssl/xray/xray.crt
key     = /etc/ssl/xray/xray.key

[ssh-ssl-443-direct]
accept  = 0.0.0.0:443
connect = 127.0.0.1:22
cert    = /etc/ssl/xray/xray.crt
key     = /etc/ssl/xray/xray.key

[ssh-ssl-465]
accept  = 0.0.0.0:465
connect = 127.0.0.1:22
cert    = /etc/ssl/xray/xray.crt
key     = /etc/ssl/xray/xray.key

[ssh-ssl-777]
accept  = 0.0.0.0:777
connect = 127.0.0.1:22
cert    = /etc/ssl/xray/xray.crt
key     = /etc/ssl/xray/xray.key

[ssh-ssl-900]
accept  = 0.0.0.0:900
connect = 127.0.0.1:22
cert    = /etc/ssl/xray/xray.crt
key     = /etc/ssl/xray/xray.key
EOF2

  mkdir -p /var/log/stunnel4 /var/run/stunnel4
  sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/stunnel4 2>/dev/null
  systemctl enable stunnel4 2>/dev/null
  systemctl restart stunnel4 2>/dev/null
  echo -e "\033[0;32m[OK]\033[0m Stunnel SSL/TLS configured"

  # ── Update nginx: port 443 tidak conflict dengan stunnel ──
  # Nginx handle TLS untuk xray, stunnel handle port lain
  nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null

  echo -e "\033[0;32m[OK]\033[0m SSH setup selesai"
}

setup_ssh_ws "$1"
