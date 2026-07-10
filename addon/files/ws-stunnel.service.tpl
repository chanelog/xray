[Unit]
Description=SSH Over Websocket Python (backend untuk SSH-SSL / stunnel4)
Documentation=https://google.com
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
Restart=on-failure
ExecStart=__PYTHON_BIN__ -O /usr/local/bin/ws-stunnel __WS_STUNNEL_LOCAL_PORT__

[Install]
WantedBy=multi-user.target
