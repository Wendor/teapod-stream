// Adapted from sing-box v1.14.4 experimental/libbox/config.go (platformInterfaceStub, interfaceMonitorStub).
// SPDX-License-Identifier: GPL-3.0-or-later

package teapodcore

import (
	"context"
	"net/netip"
	"os"
	"sync"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/dns"
	"github.com/sagernet/sing-box/option"
	tun "github.com/sagernet/sing-tun"
	"github.com/sagernet/sing/common/control"
	"github.com/sagernet/sing/common/logger"
	"github.com/sagernet/sing/common/x/list"
)

// boxPlatform — a platform interface without platform capabilities: sing-box runs
// behind tun2socks (no TUN inbound), the app's sockets are excluded from the VPN by the service itself.

type boxPlatform struct{}

var (
	protectMu sync.Mutex
	protectFn func(fd int)
)

// setProtectFd sets VpnService.protect for sing-box sockets (nil — remove).
func setProtectFd(f func(fd int)) {
	protectMu.Lock()
	protectFn = f
	protectMu.Unlock()
}

func protectFd(fd int) {
	protectMu.Lock()
	f := protectFn
	protectMu.Unlock()
	if f != nil {
		f(fd)
	}
}

func (s *boxPlatform) Initialize(networkManager adapter.NetworkManager) error {
	return nil
}

func (s *boxPlatform) UsePlatformAutoDetectInterfaceControl() bool {
	return true
}

// Every outgoing socket goes through VpnService.protect, as with xray: bare Go sockets
// bypass bionic's netd hooks and after a network change (LTE → Wi-Fi), until the old network's
// linger ends, go to the wrong place — the first hysteria2 QUIC handshake hangs for 15 s.
func (s *boxPlatform) AutoDetectInterfaceControl(fd int) error {
	protectFd(fd)
	return nil
}

func (s *boxPlatform) UsePlatformInterface() bool {
	return false
}

func (s *boxPlatform) OpenInterface(options *tun.Options, platformOptions option.TunPlatformOptions) (tun.Tun, error) {
	return nil, os.ErrInvalid
}

func (s *boxPlatform) ProcessPlatformOptions(options option.TunPlatformOptions) error {
	return nil
}

func (s *boxPlatform) UsePlatformDefaultInterfaceMonitor() bool {
	return true
}

func (s *boxPlatform) CreateDefaultInterfaceMonitor(logger logger.Logger) tun.DefaultInterfaceMonitor {
	return (*boxInterfaceMonitor)(nil)
}

func (s *boxPlatform) UsePlatformNetworkInterfaces() bool {
	return false
}

func (s *boxPlatform) NetworkInterfaces() ([]adapter.NetworkInterface, error) {
	return nil, os.ErrInvalid
}

func (s *boxPlatform) UnderNetworkExtension() bool {
	return false
}

func (s *boxPlatform) NetworkExtensionIncludeAllNetworks() bool {
	return false
}

func (s *boxPlatform) ClearDNSCache() {
}

func (s *boxPlatform) RequestPermissionForWIFIState() error {
	return nil
}

func (s *boxPlatform) UsePlatformWIFIMonitor() bool {
	return false
}

func (s *boxPlatform) ReadWIFIState(ctx context.Context) adapter.WIFIState {
	return adapter.WIFIState{}
}

// On Android sing-box always looks up the owner of every connection. Behind tun2socks
// the source is 127.0.0.1, i.e. ourselves: without a platform lookup it goes to
// netlink, gets a SELinux denial and logs "failed to search process" for every
// connection. An empty owner (UserId -1) disables the lookup without errors.
func (s *boxPlatform) UsePlatformConnectionOwnerFinder() bool {
	return true
}

func (s *boxPlatform) FindConnectionOwner(request *adapter.FindConnectionOwnerRequest) (*adapter.ConnectionOwner, error) {
	return &adapter.ConnectionOwner{UserId: -1}, nil
}

func (s *boxPlatform) UsePlatformNotification() bool {
	return false
}

func (s *boxPlatform) SendNotification(notification *adapter.Notification) error {
	return nil
}

func (s *boxPlatform) CancelNotification(identifier string, typeID int32) error {
	return nil
}

func (s *boxPlatform) MyInterfaceAddress() []netip.Addr {
	return nil
}

func (s *boxPlatform) UsePlatformNeighborResolver() bool {
	return false
}

func (s *boxPlatform) StartNeighborMonitor(listener adapter.NeighborUpdateListener) error {
	return os.ErrInvalid
}

func (s *boxPlatform) CloseNeighborMonitor(listener adapter.NeighborUpdateListener) error {
	return nil
}

func (s *boxPlatform) UsePlatformShell() bool {
	return false
}

func (s *boxPlatform) CheckPlatformShell() error {
	return nil
}

func (s *boxPlatform) OpenShellSession(user *adapter.PlatformUser, command string, env []string, term string, rows int32, cols int32) (adapter.ShellSession, error) {
	return nil, os.ErrInvalid
}

func (s *boxPlatform) LookupSFTPServer() (string, error) {
	return "", os.ErrInvalid
}

func (s *boxPlatform) ReadSystemSSHHostKey() ([]byte, error) {
	return nil, os.ErrInvalid
}

func (s *boxPlatform) TailscaleHostname() string {
	return ""
}

func (s *boxPlatform) UsePlatformBridge() bool {
	return false
}

func (s *boxPlatform) CreateBridge(options adapter.BridgeOptions) (adapter.BridgeSession, error) {
	return nil, os.ErrInvalid
}

func (s *boxPlatform) LookupUser(username string) (*adapter.PlatformUser, error) {
	return nil, os.ErrInvalid
}

func (s *boxPlatform) UsePlatformLocalDNSTransport() bool {
	return false
}

func (s *boxPlatform) LocalDNSTransport() dns.TransportConstructorFunc[option.LocalDNSServerOptions] {
	return nil
}

type boxInterfaceMonitor struct{}

func (s *boxInterfaceMonitor) Start() error {
	// A monitor without events: the service handles network changes with a full reconnect.
	return nil
}

func (s *boxInterfaceMonitor) Close() error {
	return nil
}

func (s *boxInterfaceMonitor) DefaultInterface() *control.Interface {
	return nil
}

func (s *boxInterfaceMonitor) OverrideAndroidVPN() bool {
	return false
}

func (s *boxInterfaceMonitor) AndroidVPNEnabled() bool {
	return false
}

func (s *boxInterfaceMonitor) RegisterCallback(callback tun.DefaultInterfaceUpdateCallback) *list.Element[tun.DefaultInterfaceUpdateCallback] {
	return nil
}

func (s *boxInterfaceMonitor) UnregisterCallback(element *list.Element[tun.DefaultInterfaceUpdateCallback]) {
}

func (s *boxInterfaceMonitor) RegisterMyInterface(interfaceName string) {
}

func (s *boxInterfaceMonitor) MyInterfaces() []string {
	return nil
}
