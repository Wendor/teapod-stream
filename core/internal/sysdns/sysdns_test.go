package sysdns

import (
	"context"
	"net/netip"
	"testing"

	"github.com/miekg/dns"
	"github.com/sagernet/sing-box/option"
)

func query(name string, qtype uint16) *dns.Msg {
	m := new(dns.Msg)
	m.SetQuestion(name, qtype)
	return m
}

func TestExchangeResolvesLocalhost(t *testing.T) {
	tr := New("dns-local", option.LocalDNSServerOptions{})
	req := query("localhost.", dns.TypeA)
	resp, err := tr.Exchange(context.Background(), req)
	if err != nil {
		t.Fatal(err)
	}
	if resp.Id != req.Id {
		t.Fatalf("response id %d; want %d", resp.Id, req.Id)
	}
	if len(resp.Question) != 1 || resp.Question[0].Name != "localhost." {
		t.Fatalf("response question %v; want localhost.", resp.Question)
	}
	var found bool
	for _, rr := range resp.Answer {
		if a, ok := rr.(*dns.A); ok && netip.MustParseAddr(a.A.String()) == netip.MustParseAddr("127.0.0.1") {
			found = true
		}
	}
	if !found {
		t.Fatalf("no 127.0.0.1 in %v", resp.Answer)
	}
}

// The resolver gets the absolute name: without the terminal dot it may append a
// search domain and answer for another name.
func TestExchangeKeepsNameAbsolute(t *testing.T) {
	tr := New("dns-local", option.LocalDNSServerOptions{})
	var asked string
	tr.lookup = func(_ context.Context, _, host string) ([]netip.Addr, error) {
		asked = host
		return []netip.Addr{netip.MustParseAddr("192.0.2.1")}, nil
	}
	if _, err := tr.Exchange(context.Background(), query("missing.example.", dns.TypeA)); err != nil {
		t.Fatal(err)
	}
	if asked != "missing.example." {
		t.Fatalf("resolver asked for %q; want missing.example.", asked)
	}
}

func TestExchangeRejectsNonIPQueries(t *testing.T) {
	tr := New("dns-local", option.LocalDNSServerOptions{})
	if _, err := tr.Exchange(context.Background(), query("example.com.", dns.TypeTXT)); err == nil {
		t.Fatal("TXT must not be answered by the system resolver")
	}
}
