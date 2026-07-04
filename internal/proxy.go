package internal

import (
	"io"
	"net"
	"time"

	"github.com/gorilla/websocket"
)

func Proxy(ws *websocket.Conn, backend string) {

	tcp, err := net.DialTimeout(
		"tcp",
		backend,
		10*time.Second,
	)

	if err != nil {
		ws.Close()
		return
	}

	go wsToTCP(ws, tcp)
	go tcpToWS(tcp, ws)

	select {}

}

func wsToTCP(ws *websocket.Conn, tcp net.Conn) {

	defer ws.Close()
	defer tcp.Close()

	for {

		_, data, err := ws.ReadMessage()

		if err != nil {
			return
		}

		_, err = tcp.Write(data)

		if err != nil {
			return
		}

	}

}

func tcpToWS(tcp net.Conn, ws *websocket.Conn) {

	defer ws.Close()
	defer tcp.Close()

	buf := make([]byte, 32768)

	for {

		n, err := tcp.Read(buf)

		if err != nil {

			if err != io.EOF {
			}

			return
		}

		err = ws.WriteMessage(
			websocket.BinaryMessage,
			buf[:n],
		)

		if err != nil {
			return
		}

	}

}
