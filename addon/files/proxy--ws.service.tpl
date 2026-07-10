[Unit]
Description=Proxy WebSocket SSH Tunnel (proxy--ws / wstunnel)
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/proxy--ws
Restart=always
RestartSec=5
StartLimitIntervalSec=0
KillMode=process
StandardOutput=append:/var/log/proxy--ws.log
StandardError=append:/var/log/proxy--ws.err

[Install]
WantedBy=multi-user.target
