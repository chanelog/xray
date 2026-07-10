# ============================================================
#   HAProxy - SNI Router untuk port 443
#   SNI cocok domain Xray  -> Nginx (127.0.0.1:__NGINX_TLS_INTERNAL_PORT__)
#   SNI lain / gak ada SNI -> Stunnel4 SSH-SSL (127.0.0.1:__STUNNEL_SSL_PORT__)
#   Generated otomatis oleh addon/install-haproxy.sh — JANGAN edit manual,
#   edit addon/files/haproxy.cfg.tpl di repo lalu install ulang addon ini.
# ============================================================
global
    log /dev/log local0
    maxconn 4096
    daemon

defaults
    log     global
    mode    tcp
    option  tcplog
    timeout connect 5s
    timeout client  1h
    timeout server  1h

frontend ft_tls_443
    bind *:443
    tcp-request inspect-delay 5s
    tcp-request content accept if { req.ssl_hello_type 1 }
    use_backend bk_xray if { req.ssl_sni -i __DOMAIN__ }
    default_backend bk_sshssl

backend bk_xray
    server xray1 127.0.0.1:__NGINX_TLS_INTERNAL_PORT__

backend bk_sshssl
    server sshssl1 127.0.0.1:__STUNNEL_SSL_PORT__
