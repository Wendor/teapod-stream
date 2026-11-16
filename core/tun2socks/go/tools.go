//go:build tools

package tun2socks

// This file ensures golang.org/x/mobile/bind is a module dependency
// so that gobind can find it at build time.
import _ "golang.org/x/mobile/bind"
import _ "golang.org/x/mobile/bind/java"
