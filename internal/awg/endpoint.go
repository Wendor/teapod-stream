//go:build with_gvisor

// Adapted from sing-box v1.14.4 protocol/wireguard/endpoint.go and transport/wireguard/endpoint.go.
// SPDX-License-Identifier: GPL-3.0-or-later

package awg

import (
	"context"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"net"
	"net/netip"
	"strings"
	"sync/atomic"

	"github.com/amnezia-vpn/amneziawg-go/v3/device"
	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/adapter/endpoint"
	"github.com/sagernet/sing-box/common/dialer"
	"github.com/sagernet/sing-box/common/iponly"
	"github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing/common/bufio"
	E "github.com/sagernet/sing/common/exceptions"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
	"github.com/sagernet/sing/service"
)

const defaultMTU = 1408

// RegisterEndpoint registers the "awg" type in the sing-box endpoint registry.
func RegisterEndpoint(registry *endpoint.Registry) {
	endpoint.Register[Options](registry, TypeAWG, NewEndpoint)
}

var _ adapter.Endpoint = (*Endpoint)(nil)

// Endpoint — an AmneziaWG client with a single peer on the sing-box gvisor stack.
type Endpoint struct {
	endpoint.Adapter
	ctx       context.Context
	logger    log.ContextLogger
	dnsRouter adapter.DNSRouter
	dialer    N.Dialer
	ipcConfig string
	server    M.Socksaddr
	stack     *stackDevice
	device    *device.Device
	started   atomic.Bool
}

func NewEndpoint(ctx context.Context, router adapter.Router, logger log.ContextLogger, tag string, options Options) (adapter.Endpoint, error) {
	if options.System {
		return nil, E.New("awg: system interface is not supported")
	}
	if len(options.Peers) != 1 {
		return nil, E.New("awg: exactly one peer is required, got ", len(options.Peers))
	}
	peer := options.Peers[0]
	if len(peer.Reserved) != 0 {
		return nil, E.New("awg: reserved is not supported")
	}
	if err := options.Amnezia.Validate(); err != nil {
		return nil, err
	}
	ipcConfig, err := buildIpcConfig(options)
	if err != nil {
		return nil, err
	}
	outboundDialer, err := dialer.NewWithOptions(dialer.Options{
		Context:          ctx,
		Options:          options.DialerOptions,
		RemoteIsDomain:   !M.ParseAddr(peer.Address).IsValid(),
		ResolverOnDetour: true,
	})
	if err != nil {
		return nil, err
	}
	mtu := options.MTU
	if mtu == 0 {
		mtu = defaultMTU
	}
	stack, err := newStackDevice(mtu, options.Address)
	if err != nil {
		return nil, err
	}
	return &Endpoint{
		Adapter:   endpoint.NewAdapterWithDialerOptions(TypeAWG, tag, []string{N.NetworkTCP, N.NetworkUDP}, options.DialerOptions),
		ctx:       ctx,
		logger:    logger,
		dnsRouter: service.FromContext[adapter.DNSRouter](ctx),
		dialer:    outboundDialer,
		ipcConfig: ipcConfig,
		server:    M.ParseSocksaddrHostPort(peer.Address, peer.Port),
		stack:     stack,
	}, nil
}

func decodeKey(name, value string) (string, error) {
	raw, err := base64.StdEncoding.DecodeString(value)
	if err != nil {
		return "", fmt.Errorf("awg: decode %s: %w", name, err)
	}
	return hex.EncodeToString(raw), nil
}

// buildIpcConfig — amneziawg-go UAPI: device key, AWG parameters, then the peer.
// In connect mode the endpoint address isn't used for sending, so for
// a domain server a placeholder with the same port is substituted.
func buildIpcConfig(options Options) (string, error) {
	peer := options.Peers[0]
	privateKey, err := decodeKey("private_key", options.PrivateKey)
	if err != nil {
		return "", err
	}
	publicKey, err := decodeKey("public_key", peer.PublicKey)
	if err != nil {
		return "", err
	}
	amnezia, err := options.Amnezia.IpcConfig()
	if err != nil {
		return "", err
	}
	var b strings.Builder
	b.WriteString("private_key=" + privateKey + "\n")
	b.WriteString(amnezia)
	b.WriteString("public_key=" + publicKey + "\n")
	if peer.PreSharedKey != "" {
		psk, err := decodeKey("pre_shared_key", peer.PreSharedKey)
		if err != nil {
			return "", err
		}
		b.WriteString("preshared_key=" + psk + "\n")
	}
	addr := M.ParseAddr(peer.Address)
	if !addr.IsValid() {
		addr = netip.IPv4Unspecified()
	}
	b.WriteString("endpoint=" + netip.AddrPortFrom(addr, peer.Port).String() + "\n")
	if peer.PersistentKeepaliveInterval != 0 {
		fmt.Fprintf(&b, "persistent_keepalive_interval=%d\n", peer.PersistentKeepaliveInterval)
	}
	allowed := peer.AllowedIPs
	if len(allowed) == 0 {
		allowed = []netip.Prefix{netip.MustParsePrefix("0.0.0.0/0"), netip.MustParsePrefix("::/0")}
	}
	for _, prefix := range allowed {
		b.WriteString("allowed_ip=" + prefix.String() + "\n")
	}
	return b.String(), nil
}

func (w *Endpoint) Start(stage adapter.StartStage, scope *adapter.Scope) error {
	if stage != adapter.StartStatePostStart {
		return nil
	}
	bind := newClientBind(w.ctx, w.logger, w.dialer, w.server)
	wgDevice := device.NewDevice(w.stack, bind, &device.Logger{
		Verbosef: func(format string, args ...any) {
			w.logger.Debug(fmt.Sprintf(strings.ToLower(format), args...))
		},
		Errorf: func(format string, args ...any) {
			w.logger.Error(fmt.Sprintf(strings.ToLower(format), args...))
		},
	})
	if err := wgDevice.IpcSet(w.ipcConfig); err != nil {
		wgDevice.Close()
		return E.Cause(err, "awg: set ipc config")
	}
	w.stack.Reconfigured()
	if err := w.stack.Start(); err != nil {
		wgDevice.Close()
		return err
	}
	if err := wgDevice.Up(); err != nil {
		wgDevice.Close()
		return err
	}
	w.device = wgDevice
	w.started.Store(true)
	scope.Add(w.close)
	return nil
}

func (w *Endpoint) close() error {
	w.started.Store(false)
	if w.device != nil {
		w.device.Close()
		w.device = nil
	}
	return nil
}

func (w *Endpoint) Close() error {
	if err := w.close(); err != nil {
		return err
	}
	return w.stack.Close()
}

func (w *Endpoint) DialContext(ctx context.Context, network string, destination M.Socksaddr) (net.Conn, error) {
	if !w.started.Load() {
		return nil, E.New("AmneziaWG is not ready yet")
	}
	if destination.IsDomain() {
		addresses, err := w.dnsRouter.Lookup(ctx, destination.Fqdn, adapter.DNSQueryOptions{})
		if err != nil {
			return nil, err
		}
		return N.DialSerial(ctx, w.stack, network, destination, addresses)
	} else if !destination.Addr.IsValid() {
		return nil, E.New("invalid destination: ", destination)
	}
	return w.stack.DialContext(ctx, network, destination)
}

func (w *Endpoint) ListenPacket(ctx context.Context, destination M.Socksaddr) (net.PacketConn, error) {
	if !w.started.Load() {
		return nil, E.New("AmneziaWG is not ready yet")
	}
	if destination.IsDomain() {
		addresses, err := w.dnsRouter.Lookup(ctx, destination.Fqdn, adapter.DNSQueryOptions{})
		if err != nil {
			return nil, err
		}
		packetConn, address, err := N.ListenSerial(ctx, w.stack, destination, addresses)
		if err != nil {
			return nil, err
		}
		return bufio.NewNATPacketConn(bufio.NewPacketConn(iponly.NewPacketConn(w.logger, packetConn)),
			M.SocksaddrFrom(address, destination.Port), destination), nil
	}
	packetConn, err := w.stack.ListenPacket(ctx, destination)
	if err != nil {
		return nil, err
	}
	return iponly.NewPacketConn(w.logger, packetConn), nil
}
