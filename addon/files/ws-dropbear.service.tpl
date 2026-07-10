[Unit]
Description=Websocket-Dropbear (SSH-WS, backend Dropbear)
Documentation=https://google.com
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=__PYTHON_BIN__ -O /usr/local/bin/ws-dropbear __WS_DROPBEAR_PORT__
Restart=on-failure

[Install]
WantedBy=multi-user.target
