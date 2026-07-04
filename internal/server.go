package internal

import (
	"log"
	"net/http"

	"github.com/gorilla/websocket"
)

type Server struct {
	cfg Config
}

func NewServer(cfg Config) *Server {
	return &Server{
		cfg: cfg,
	}
}

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
	ReadBufferSize:  4096,
	WriteBufferSize: 4096,
}

func (s *Server) handleWS(w http.ResponseWriter, r *http.Request) {

	if r.URL.Path != s.cfg.Path {
		http.NotFound(w, r)
		return
	}

	conn, err := upgrader.Upgrade(w, r, nil)

	if err != nil {
		log.Println(err)
		return
	}

	go Proxy(conn, s.cfg.Backend)

}

func (s *Server) Start() error {

	http.HandleFunc(s.cfg.Path, s.handleWS)

	log.Printf("Listening : %s", s.cfg.Listen)
	log.Printf("Backend  : %s", s.cfg.Backend)
	log.Printf("WS Path  : %s", s.cfg.Path)

	return http.ListenAndServe(s.cfg.Listen, nil)

}
