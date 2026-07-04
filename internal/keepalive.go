package internal

import (
	"time"

	"github.com/gorilla/websocket"
)

const PingInterval = 30 * time.Second

func KeepAlive(conn *websocket.Conn) {

	ticker := time.NewTicker(PingInterval)

	defer ticker.Stop()

	for {

		select {

		case <-ticker.C:

			err := conn.WriteControl(
				websocket.PingMessage,
				[]byte("ping"),
				time.Now().Add(5*time.Second),
			)

			if err != nil {
				return
			}

		}

	}

}
