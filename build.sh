#!/bin/bash
set -e

APP=sshws

echo "[*] Download dependency..."
go mod tidy

echo "[*] Build Linux AMD64..."
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
go build -ldflags="-s -w" \
-o build/${APP}-linux-amd64 ./cmd/sshws

echo "[*] Build Linux ARM64..."
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
go build -ldflags="-s -w" \
-o build/${APP}-linux-arm64 ./cmd/sshws

echo "[*] Build Linux ARM..."
CGO_ENABLED=0 GOOS=linux GOARCH=arm \
GOARM=7 \
go build -ldflags="-s -w" \
-o build/${APP}-linux-armv7 ./cmd/sshws

echo "Done."
