#!/usr/bin/env bash
# proxy--ws lance wstunnel en mode serveur WebSocket tunnel SSH

DOMAIN="__DOMAIN__"
WS_LISTEN_ADDR="0.0.0.0"
WS_LISTEN_PORT="__PORT__"
BACKEND_HOST="127.0.0.1"
BACKEND_PORT="22"
WSTUNNEL_BIN="/usr/local/bin/wstunnel"
PID_FILE="/var/run/proxy--ws.pid"
LOG_FILE="/var/log/proxy--ws.log"

echo "Démarrage du tunnel WebSocket sur ws://$DOMAIN:$WS_LISTEN_PORT vers $BACKEND_HOST:$BACKEND_PORT"
exec $WSTUNNEL_BIN server "ws://$DOMAIN:$WS_LISTEN_PORT" --restrict-to "$BACKEND_HOST:$BACKEND_PORT"
