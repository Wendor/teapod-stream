//go:build with_gvisor

package awg

import (
	"context"
	"encoding/base64"
	"strings"
	"testing"

	"github.com/sagernet/sing-box/adapter/endpoint"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/json"
	"github.com/sagernet/sing/service"
)

func TestAmneziaIpcConfigOrderAndOmitsZero(t *testing.T) {
	o := AmneziaOptions{
		Jc: 4, Jmin: 40, Jmax: 70, S1: 16, S4: 16,
		H1: "100-200", H4: "500", I1: "<b 0xc0ffee><r 16>",
		ContentPaddingAddition: "0-32", RekeyAfterTime: "120", MaxHandshakeAttempts: "20",
	}
	got, err := o.IpcConfig()
	if err != nil {
		t.Fatal(err)
	}
	want := "jc=4\njmin=40\njmax=70\ns1=16\ns4=16\nh1=100-200\nh4=500\ni1=<b 0xc0ffee><r 16>\n" +
		"content_padding_addition=0-32\nrekey_after_time=120\nmax_handshake_attempts=20\n"
	if got != want {
		t.Fatalf("got\n%s\nwant\n%s", got, want)
	}
}

func TestAmneziaHeaderKeyIsHex(t *testing.T) {
	key := make([]byte, 32)
	for i := range key {
		key[i] = byte(i)
	}
	o := AmneziaOptions{S1: 12, S2: 12, S3: 12, S4: 12, HeaderProtectionKey: base64.StdEncoding.EncodeToString(key)}
	got, err := o.IpcConfig()
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(got, "header_protection_key=000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f\n") {
		t.Fatalf("hex key missing: %s", got)
	}
	o.HeaderProtectionKey = "not base64!"
	if _, err := o.IpcConfig(); err == nil {
		t.Fatal("invalid base64 must fail")
	}
}

func TestAmneziaValidateHeaderProtectionNeedsPaddings(t *testing.T) {
	o := AmneziaOptions{S1: 16, S2: 16, S3: 0, S4: 16, HeaderProtectionKey: base64.StdEncoding.EncodeToString(make([]byte, 32))}
	if err := o.Validate(); err == nil || !strings.Contains(err.Error(), "header protection requires s1-s4 >= 12") {
		t.Fatalf("err = %v", err)
	}
	o.S3 = 12
	if err := o.Validate(); err != nil {
		t.Fatal(err)
	}
}

func TestEndpointOptionsUnmarshal(t *testing.T) {
	registry := endpoint.NewRegistry()
	RegisterEndpoint(registry)
	ctx := service.ContextWith[option.EndpointOptionsRegistry](context.Background(), registry)
	config := `{"endpoints":[{"type":"awg","tag":"proxy","address":["10.8.0.2/32"],"private_key":"x",
		"peers":[{"address":"vpn.example.com","port":51820,"public_key":"y","allowed_ips":["0.0.0.0/0"]}],
		"amnezia":{"jc":4,"h1":"100-200"}}]}`
	opts, err := json.UnmarshalExtendedContext[option.Options](ctx, []byte(config))
	if err != nil {
		t.Fatal(err)
	}
	ep := opts.Endpoints[0]
	got, ok := ep.Options.(*Options)
	if ep.Type != TypeAWG || !ok {
		t.Fatalf("type %q, options %T", ep.Type, ep.Options)
	}
	if got.Amnezia.Jc != 4 || got.Amnezia.H1 != "100-200" || got.Peers[0].Port != 51820 {
		t.Fatalf("unexpected options: %+v", got)
	}
}

// AWG 3.1: a server with RandomTrailers appends a tail to the handshake — without the flag the client
// drops the response as "unknown type".
func TestAmneziaIpcConfigFlags(t *testing.T) {
	got, err := AmneziaOptions{RandomTrailers: true, DisableCookies: true}.IpcConfig()
	if err != nil {
		t.Fatal(err)
	}
	if want := "random_trailers=true\ndisable_cookies=true\n"; got != want {
		t.Fatalf("got\n%s\nwant\n%s", got, want)
	}
	var o AmneziaOptions
	if err := json.Unmarshal([]byte(`{"random_trailers":true,"disable_cookies":true}`), &o); err != nil || !o.RandomTrailers || !o.DisableCookies {
		t.Fatalf("unmarshal: %+v %v", o, err)
	}
}
