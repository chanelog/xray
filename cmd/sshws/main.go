package main

import (
	"log"

	"github.com/chanelog/sshws/internal"
)

func main() {

	cfg := internal.DefaultConfig()

	server := internal.NewServer(cfg)

	log.Printf("SSHWS listening on %s", cfg.Listen)

	if err := server.Start(); err != nil {
		log.Fatal(err)
	}

}
