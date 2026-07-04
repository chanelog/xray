package internal

import (
	"net"
	"sync"

	"github.com/gorilla/websocket"
)

type Connection struct {
	ws   *websocket.Conn
	tcp  net.Conn
	once sync.Once
}

func NewConnection(ws *websocket.Conn, tcp net.Conn) *Connection {
	return &Connection{
		ws:  ws,
		tcp: tcp,
	}
}

func (c *Connection) Close() {
	c.once.Do(func() {
		if c.ws != nil {
			_ = c.ws.Close()
		}
		if c.tcp != nil {
			_ = c.tcp.Close()
		}
	})
}
