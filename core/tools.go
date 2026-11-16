//go:build tools

package teapodcore

// Keeps golang.org/x/mobile/bind (and its dependencies) in the module graph so that gobind
// finds them when gomobile builds the AAR.
import (
	_ "golang.org/x/mobile/bind"
	_ "golang.org/x/mobile/bind/java"
)
