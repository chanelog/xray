package internal

import (
	"log"
	"net/http"
	"time"

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
	ReadBufferSize:  BufferSize,
	WriteBufferSize: BufferSize,
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

func (s *Server) handleWS(w http.ResponseWriter, r *http.Request) {

	if r.Method != http.MethodGet {
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
		return
	}

	if r.URL.Path != s.cfg.Path {
		http.NotFound(w, r)
		return
	}

	conn, err := upgrader.Upgrade(w, r, nil)

	if err != nil {
		log.Println(err)
		return
	}

	conn.SetReadLimit(1024 * 1024)

	conn.SetReadDeadline(
		time.Now().Add(ReadTimeout),
	)

	conn.SetPongHandler(func(string) error {

		conn.SetReadDeadline(
			time.Now().Add(ReadTimeout),
		)

		return nil
	})

	go Proxy(conn, s.cfg.Backend)

}

func (s *Server) Start() error {

	mux := http.NewServeMux()

	mux.HandleFunc(
		s.cfg.Path,
		s.handleWS,
	)

	server := &http.Server{

		Addr:         s.cfg.Listen,
		Handler:      mux,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	log.Printf("===================================")
	log.Printf(" SSHWS SERVER")
	log.Printf("===================================")
	log.Printf("Listen  : %s", s.cfg.Listen)
	log.Printf("Backend : %s", s.cfg.Backend)
	log.Printf("Path    : %s", s.cfg.Path)
	log.Printf("===================================")

	return server.ListenAndServe()

}
