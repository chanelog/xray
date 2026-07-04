package internal

import (
	"log"
	"os"
)

var Logger = log.New(
	os.Stdout,
	"[SSHWS] ",
	log.LstdFlags|log.Lshortfile,
)

func Info(v ...any) {
	Logger.Println(v...)
}

func Error(v ...any) {
	Logger.Println(v...)
}
