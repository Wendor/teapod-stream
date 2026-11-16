package teapodcore

import (
	"testing"

	boxlog "github.com/sagernet/sing-box/log"
)

// The sing-box 1.14 platform formatter always colors output (log.disable_color doesn't
// affect it) — escape codes aren't needed in logcat and vpn_log.txt.
func TestBoxLogLineStripsColors(t *testing.T) {
	got := boxLogLine(boxlog.LevelDebug, "\x1b[37mDEBUG\x1b[0m[0003] [\x1b[38;5;231m3995781847\x1b[0m 0ms] router: ok\n")
	if want := "[Info] DEBUG[0003] [3995781847 0ms] router: ok"; got != want {
		t.Fatalf("got %q want %q", got, want)
	}
	if got := boxLogLine(boxlog.LevelError, "x"); got != "[Error] x" {
		t.Fatalf("error level: %q", got)
	}
	if got := boxLogLine(boxlog.LevelWarn, "x"); got != "[Warning] x" {
		t.Fatalf("warn level: %q", got)
	}
}
