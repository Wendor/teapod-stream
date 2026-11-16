// Package awg — an AmneziaWG endpoint for sing-box on amneziawg-go.
package awg

import (
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"

	"github.com/sagernet/sing-box/option"
)

// TypeAWG — the endpoint type in the sing-box config.
const TypeAWG = "awg"

// Options — sing-box WireGuard endpoint options plus AmneziaWG parameters.
type Options struct {
	option.WireGuardEndpointOptions
	Amnezia AmneziaOptions `json:"amnezia"`
}

// AmneziaOptions — AmneziaWG 3.1 parameters (amneziawg-go UAPI keys).
// Zero/empty values aren't passed: AWG treats them as zero.
type AmneziaOptions struct {
	Jc   int `json:"jc,omitempty"`
	Jmin int `json:"jmin,omitempty"`
	Jmax int `json:"jmax,omitempty"`
	S1   int `json:"s1,omitempty"`
	S2   int `json:"s2,omitempty"`
	S3   int `json:"s3,omitempty"`
	S4   int `json:"s4,omitempty"`

	H1 string `json:"h1,omitempty"`
	H2 string `json:"h2,omitempty"`
	H3 string `json:"h3,omitempty"`
	H4 string `json:"h4,omitempty"`
	I1 string `json:"i1,omitempty"`
	I2 string `json:"i2,omitempty"`
	I3 string `json:"i3,omitempty"`
	I4 string `json:"i4,omitempty"`
	I5 string `json:"i5,omitempty"`

	// HeaderProtectionKey — base64, as in .conf; hex goes to UAPI.
	HeaderProtectionKey    string `json:"header_protection_key,omitempty"`
	ContentPaddingAddition string `json:"content_padding_addition,omitempty"`
	RekeyAfterTime         string `json:"rekey_after_time,omitempty"`
	RekeyTimeout           string `json:"rekey_timeout,omitempty"`
	RejectAfterTime        string `json:"reject_after_time,omitempty"`
	KeepaliveTimeout       string `json:"keepalive_timeout,omitempty"`
	MaxHandshakeAttempts   string `json:"max_handshake_attempts,omitempty"`
	RandomTrailers         bool   `json:"random_trailers,omitempty"`
	DisableCookies         bool   `json:"disable_cookies,omitempty"`
}

// Validate checks AWG constraints that would otherwise surface only at the handshake.
func (o AmneziaOptions) Validate() error {
	if o.HeaderProtectionKey != "" && (o.S1 < 12 || o.S2 < 12 || o.S3 < 12 || o.S4 < 12) {
		return errors.New("awg: header protection requires s1-s4 >= 12")
	}
	return nil
}

// IpcConfig — device-level amneziawg-go UAPI lines in a fixed order.
func (o AmneziaOptions) IpcConfig() (string, error) {
	var b strings.Builder
	ints := []struct {
		key string
		v   int
	}{{"jc", o.Jc}, {"jmin", o.Jmin}, {"jmax", o.Jmax}, {"s1", o.S1}, {"s2", o.S2}, {"s3", o.S3}, {"s4", o.S4}}
	for _, kv := range ints {
		if kv.v != 0 {
			fmt.Fprintf(&b, "%s=%d\n", kv.key, kv.v)
		}
	}
	key := ""
	if o.HeaderProtectionKey != "" {
		raw, err := base64.StdEncoding.DecodeString(o.HeaderProtectionKey)
		if err != nil {
			return "", fmt.Errorf("awg: header_protection_key: %w", err)
		}
		key = hex.EncodeToString(raw)
	}
	strs := []struct{ key, v string }{
		{"h1", o.H1}, {"h2", o.H2}, {"h3", o.H3}, {"h4", o.H4},
		{"i1", o.I1}, {"i2", o.I2}, {"i3", o.I3}, {"i4", o.I4}, {"i5", o.I5},
		{"header_protection_key", key},
		{"content_padding_addition", o.ContentPaddingAddition},
		{"rekey_after_time", o.RekeyAfterTime},
		{"rekey_timeout", o.RekeyTimeout},
		{"reject_after_time", o.RejectAfterTime},
		{"keepalive_timeout", o.KeepaliveTimeout},
		{"max_handshake_attempts", o.MaxHandshakeAttempts},
	}
	for _, kv := range strs {
		if kv.v != "" {
			fmt.Fprintf(&b, "%s=%s\n", kv.key, kv.v)
		}
	}
	if o.RandomTrailers {
		b.WriteString("random_trailers=true\n")
	}
	if o.DisableCookies {
		b.WriteString("disable_cookies=true\n")
	}
	return b.String(), nil
}
