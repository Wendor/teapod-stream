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
	resp, err := tr.Exchange(context.Background(), query("localhost.", dns.TypeA))
	if err != nil {
		t.Fatal(err)
	}
	var found bool
	for _, rr := range resp.Answer {
		if a, ok := rr.(*dns.A); ok && netip.MustParseAddr(a.A.String()) == netip.MustParseAddr("127.0.0.1") {
			found = true
		}
	}
	if !found || resp.Id != 0 && resp.Question[0].Name != "localhost." {
		t.Fatalf("no 127.0.0.1 in %v", resp.Answer)
	}
}

func TestExchangeRejectsNonIPQueries(t *testing.T) {
	tr := New("dns-local", option.LocalDNSServerOptions{})
	if _, err := tr.Exchange(context.Background(), query("example.com.", dns.TypeTXT)); err == nil {
		t.Fatal("TXT must not be answered by the system resolver")
	}
}
