package teapodcore

import (
	"regexp"
	"strings"

	boxlog "github.com/sagernet/sing-box/log"
)

var ansiEscape = regexp.MustCompile(`\x1b\[[0-9;]*m`)

// boxLogLine — a sing-box log line in xray format ([Error]/[Warning]/[Info]) without
// color escape codes: the sing-box platform formatter always colors output.
func boxLogLine(level boxlog.Level, message string) string {
	tag := "[Info]"
	switch {
	case level <= boxlog.LevelError:
		tag = "[Error]"
	case level == boxlog.LevelWarn:
		tag = "[Warning]"
	}
	return tag + " " + ansiEscape.ReplaceAllString(strings.TrimRight(message, "\n"), "")
}
