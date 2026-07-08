#!/usr/bin/env python3
"""
ws-openssh.py - minimal WebSocket-disguised TCP proxy in front of local SSHD.

Rewritten for Python 3 (the original template used Python-2-only syntax:
`print log`, `import thread`, `except ... as e: e.strerror`, which does not
run on a stock Debian 11/12 box since python2 is no longer packaged there).

Behaviour matches the classic "ws-epro" style scripts used by SSH-WS client
apps (HTTP Injector, NPV Tunnel, KPN Tunnel, etc.):
  - client opens a plain TCP connection and sends an HTTP-like handshake
  - if header 'X-Real-Host' is present, proxy to that host:port
  - otherwise proxy to DEFAULT_HOST (local sshd)
  - reply with a fake "101" response so the client's WS layer is satisfied

Usage:
  ws-openssh.py <listen_port> [bind_addr] [default_host:port]

By default this binds to 127.0.0.1 only - it is meant to sit behind Nginx,
which does the real TLS termination and WebSocket proxying on 443/80.
"""
import socket
import threading
import select
import sys

BUFLEN = 4096 * 4
TIMEOUT = 60
DEFAULT_HOST = "127.0.0.1:22"
RESPONSE = (
    b"HTTP/1.1 101 Switching Protocols\r\n"
    b"Upgrade: websocket\r\n"
    b"Connection: Upgrade\r\n"
    b"Sec-WebSocket-Accept: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"
)


class Server(threading.Thread):
    def __init__(self, host, port):
        super().__init__()
        self.running = False
        self.host = host
        self.port = int(port)
        self.threads = []
        self.threads_lock = threading.Lock()
        self.log_lock = threading.Lock()

    def run(self):
        self.soc = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.soc.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.soc.settimeout(2)
        self.soc.bind((self.host, self.port))
        self.soc.listen(20)
        self.running = True
        try:
            while self.running:
                try:
                    client_sock, addr = self.soc.accept()
                    client_sock.setblocking(True)
                except socket.timeout:
                    continue
                conn = ConnectionHandler(client_sock, self, addr)
                conn.start()
                self.add_conn(conn)
        finally:
            self.running = False
            self.soc.close()

    def print_log(self, msg):
        with self.log_lock:
            print(msg, flush=True)

    def add_conn(self, conn):
        with self.threads_lock:
            if self.running:
                self.threads.append(conn)

    def remove_conn(self, conn):
        with self.threads_lock:
            if conn in self.threads:
                self.threads.remove(conn)

    def close(self):
        self.running = False
        with self.threads_lock:
            for c in list(self.threads):
                c.close()


class ConnectionHandler(threading.Thread):
    def __init__(self, client_sock, server, addr):
        super().__init__(daemon=True)
        self.client_closed = False
        self.target_closed = True
        self.client = client_sock
        self.server = server
        self.target = None
        self.log = f"Connection: {addr}"

    def close(self):
        try:
            if not self.client_closed:
                self.client.shutdown(socket.SHUT_RDWR)
                self.client.close()
        except OSError:
            pass
        finally:
            self.client_closed = True
        try:
            if not self.target_closed and self.target:
                self.target.shutdown(socket.SHUT_RDWR)
                self.target.close()
        except OSError:
            pass
        finally:
            self.target_closed = True

    def find_header(self, head: bytes, header: str):
        head_str = head.decode("latin-1", errors="ignore")
        needle = header + ": "
        idx = head_str.find(needle)
        if idx == -1:
            return ""
        start = idx + len(needle)
        end = head_str.find("\r\n", start)
        if end == -1:
            return ""
        return head_str[start:end].strip()

    def run(self):
        try:
            buf = self.client.recv(BUFLEN)

            host_port = self.find_header(buf, "X-Real-Host")
            if not host_port:
                host_port = DEFAULT_HOST

            if self.find_header(buf, "X-Split"):
                self.client.recv(BUFLEN)

            # Only allow proxying to localhost targets - this proxy is meant
            # to reach the local sshd, not act as an open relay to anywhere.
            if host_port.startswith("127.0.0.1") or host_port.startswith("localhost"):
                self.connect_target(host_port)
                self.client.sendall(RESPONSE)
                self.server.print_log(self.log + f" - CONNECT {host_port}")
                self.pipe()
            else:
                self.client.sendall(b"HTTP/1.1 403 Forbidden\r\n\r\n")
        except Exception as exc:  # noqa: BLE001
            self.server.print_log(self.log + f" - error: {exc}")
        finally:
            self.close()
            self.server.remove_conn(self)

    def connect_target(self, host_port):
        if ":" in host_port:
            host, port_s = host_port.rsplit(":", 1)
            port = int(port_s)
        else:
            host, port = host_port, 22
        addr_info = socket.getaddrinfo(host, port, proto=socket.IPPROTO_TCP)[0]
        family, socktype, proto, _, sockaddr = addr_info
        self.target = socket.socket(family, socktype, proto)
        self.target_closed = False
        self.target.connect(sockaddr)

    def pipe(self):
        socs = [self.client, self.target]
        idle = 0
        while True:
            readable, _, errored = select.select(socs, [], socs, 3)
            if errored:
                break
            if not readable:
                idle += 1
                if idle >= TIMEOUT:
                    break
                continue
            idle = 0
            for s in readable:
                try:
                    data = s.recv(BUFLEN)
                except OSError:
                    return
                if not data:
                    return
                dst = self.client if s is self.target else self.target
                try:
                    dst.sendall(data)
                except OSError:
                    return


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <port> [bind_addr] [default_host:port]")
        sys.exit(1)

    port = sys.argv[1]
    bind_addr = sys.argv[2] if len(sys.argv) > 2 else "127.0.0.1"
    global DEFAULT_HOST
    if len(sys.argv) > 3:
        DEFAULT_HOST = sys.argv[3]

    print("\n:------- ws-openssh (py3) -------:")
    print(f"Listening addr : {bind_addr}")
    print(f"Listening port : {port}")
    print(f"Default target : {DEFAULT_HOST}")
    print(":---------------------------------:\n")

    server = Server(bind_addr, port)
    server.start()
    try:
        while True:
            server.join(1)
    except KeyboardInterrupt:
        print("Stopping...")
        server.close()


if __name__ == "__main__":
    main()
