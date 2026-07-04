package internal

import (
	"io"
	"net"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

const (
	ReadTimeout  = 300 * time.Second
	WriteTimeout = 300 * time.Second
	BufferSize   = 32 * 1024
)

func Proxy(ws *websocket.Conn, backend string) {

	tcp, err := net.DialTimeout(
		"tcp",
		backend,
		10*time.Second,
	)

	if err != nil {
		_ = ws.Close()
		return
	}

	defer tcp.Close()
	defer ws.Close()

	var wg sync.WaitGroup
	wg.Add(2)

	go func() {
		defer wg.Done()
		copyWSToTCP(ws, tcp)
	}()

	go func() {
		defer wg.Done()
		copyTCPToWS(tcp, ws)
	}()

	wg.Wait()
}

func copyWSToTCP(ws *websocket.Conn, tcp net.Conn) {

	for {

		_ = ws.SetReadDeadline(time.Now().Add(ReadTimeout))

		mt, data, err := ws.ReadMessage()

		if err != nil {
			return
		}

		if mt != websocket.BinaryMessage && mt != websocket.TextMessage {
			continue
		}

		if _, err := tcp.Write(data); err != nil {
			return
		}
	}
}

func copyTCPToWS(tcp net.Conn, ws *websocket.Conn) {

	buf := make([]byte, BufferSize)

	for {

		_ = tcp.SetReadDeadline(time.Now().Add(ReadTimeout))

		n, err := tcp.Read(buf)

		if err != nil {

			if err != io.EOF {
			}

			return
		}

		_ = ws.SetWriteDeadline(time.Now().Add(WriteTimeout))

		if err := ws.WriteMessage(websocket.BinaryMessage, buf[:n]); err != nil {
			return
		}
	}
}
