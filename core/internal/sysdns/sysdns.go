// Package sysdns — the sing-box `local` DNS transport via the system resolver.
// The standard `local` reads /etc/resolv.conf, which Android doesn't have; Go on
// Android resolves via bionic (cgo), and the app's UID is excluded from the VPN.
package sysdns

import (
	"context"
	"errors"
	"net"
	"net/netip"

	"github.com/miekg/dns"
	"github.com/sagernet/sing-box/adapter"
	C "github.com/sagernet/sing-box/constant"
	boxdns "github.com/sagernet/sing-box/dns"
	"github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
)

// Register replaces the `local` transport in the DNS registry.
func Register(registry *boxdns.TransportRegistry) {
	boxdns.RegisterTransport[option.LocalDNSServerOptions](registry, C.DNSTypeLocal,
		func(_ context.Context, _ log.ContextLogger, tag string, options option.LocalDNSServerOptions) (adapter.DNSTransport, error) {
			return New(tag, options), nil
		})
}

var _ adapter.DNSTransport = (*Transport)(nil)

type Transport struct {
	boxdns.TransportAdapter
	lookup func(ctx context.Context, network, host string) ([]netip.Addr, error)
}

func New(tag string, options option.LocalDNSServerOptions) *Transport {
	return &Transport{
		TransportAdapter: boxdns.NewTransportAdapterWithLocalOptions(C.DNSTypeLocal, tag, options),
		lookup:           net.DefaultResolver.LookupNetIP,
	}
}

func (t *Transport) Start(adapter.StartStage, *adapter.Scope) error { return nil }

func (t *Transport) Close() error { return nil }

func (t *Transport) Reset() {}

// Exchange answers only A/AAAA: the system resolver doesn't return other types.
func (t *Transport) Exchange(ctx context.Context, message *dns.Msg) (*dns.Msg, error) {
	if len(message.Question) == 0 {
		return nil, errors.New("sysdns: empty question")
	}
	question := message.Question[0]
	var network string
	switch question.Qtype {
	case dns.TypeA:
		network = "ip4"
	case dns.TypeAAAA:
		network = "ip6"
	default:
		return nil, errors.New("sysdns: only A/AAAA queries are supported")
	}
	// The name stays absolute (terminal dot): without it the resolver may append a search domain
	// and answer the question with the address of another name.
	addresses, err := t.lookup(ctx, network, question.Name)
	var dnsErr *net.DNSError
	if errors.As(err, &dnsErr) && dnsErr.IsNotFound {
		return boxdns.FixedResponse(message.Id, question, nil, C.DefaultDNSTTL), nil
	}
	if err != nil {
		return nil, err
	}
	// The resolver may return IPv4 as IPv4-mapped IPv6 (::ffff:a.b.c.d); FixedResponse puts only
	// Is4() addresses into A records, so unmapped they would vanish from the answer.
	for i := range addresses {
		addresses[i] = addresses[i].Unmap()
	}
	return boxdns.FixedResponse(message.Id, question, addresses, C.DefaultDNSTTL), nil
}

func (t *Transport) ExchangeAsync(ctx context.Context, message *dns.Msg, callback func(response *dns.Msg, err error)) {
	go func() { callback(t.Exchange(ctx, message)) }()
}
