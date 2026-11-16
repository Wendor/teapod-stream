//go:build android

package teapodcore

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"time"

	coreapplog "github.com/xtls/xray-core/app/log"
	corecommlog "github.com/xtls/xray-core/common/log"
	corenet "github.com/xtls/xray-core/common/net"
	corefilesystem "github.com/xtls/xray-core/common/platform/filesystem"
	"github.com/xtls/xray-core/common/serial"
	core "github.com/xtls/xray-core/core"
	corestats "github.com/xtls/xray-core/features/stats"
	coreserial "github.com/xtls/xray-core/infra/conf/serial"
	_ "github.com/xtls/xray-core/main/distro/all"
	_ "github.com/xtls/xray-core/proxy/hysteria"
	_ "github.com/xtls/xray-core/proxy/shadowsocks_2022"
	_ "github.com/xtls/xray-core/transport/internet/hysteria"
	"github.com/xtls/xray-core/transport/internet"
	mobasset "golang.org/x/mobile/asset"

	tun2socks "github.com/Wendor/teapod-tun2socks"
)

// --- INTERFACES (gomobile-visible) ---

// VpnProtector protects outbound sockets so they bypass the VPN tunnel.
// Implement using Android's VpnService.protect(fd) to prevent routing loops.
type VpnProtector interface {
	Protect(fd int) bool
}

// XrayCallback receives status updates from xray-core.
type XrayCallback interface {
	OnStatus(status int64, message string)
}

// LogListener receives xray-core runtime log lines (error + access logs).
// Without it these lines go only to Go's stdout, which is invisible on Android —
// outbound dial failures (DPI resets, DNS errors) never reach vpn_log.txt.
type LogListener interface {
	OnLog(message string)
}

// TunValidator is called for each new connection through the TUN interface.
// Return true to allow the connection, false to deny it.
type TunValidator interface {
	OnValidate(srcIP string, srcPort int64, dstIP string, dstPort int64, protocol int64) bool
}

// ProcessFinder resolves the UID of the process owning a given connection.
// Used for per-app routing rules in xray-core.
type ProcessFinder interface {
	FindProcessByConnection(network, srcIP string, srcPort int64, destIP string, destPort int64) int64
}

// --- INTERNAL XRAY STATE ---

type xrayEngine struct {
	mu           sync.Mutex
	instance     *core.Instance
	statsManager corestats.Manager
	isRunning    bool
	cb           XrayCallback
}

var (
	// xrayMu guards the xray pointer itself; xrayEngine.mu guards its fields.
	xrayMu          sync.Mutex
	xray            *xrayEngine
	tun2socksMu     sync.Mutex
	tun2socksEngine *tun2socks.TeapodTun2socks
	logListenerMu   sync.Mutex
	logListener     LogListener
)

func currentXray() *xrayEngine {
	xrayMu.Lock()
	defer xrayMu.Unlock()
	return xray
}

// --- XRAY: INTERNAL HELPERS ---

type consoleLogWriter struct {
	logger *log.Logger
}

func (w *consoleLogWriter) Write(s string) error {
	logListenerMu.Lock()
	l := logListener
	logListenerMu.Unlock()
	if l != nil {
		// The listener logs to logcat itself; stdout would duplicate every line.
		l.OnLog(strings.TrimRight(s, "\n"))
		return nil
	}
	w.logger.Print(s)
	return nil
}

func (w *consoleLogWriter) Close() error { return nil }

func newStdoutLogWriterCreator() corecommlog.WriterCreator {
	return func() corecommlog.Writer {
		return &consoleLogWriter{logger: log.New(os.Stdout, "", 0)}
	}
}

func registerLogHandler() {
	if err := coreapplog.RegisterHandlerCreator(
		coreapplog.LogType_Console,
		func(lt coreapplog.LogType, options coreapplog.HandlerCreatorOptions) (corecommlog.Handler, error) {
			return corecommlog.NewLogger(newStdoutLogWriterCreator()), nil
		},
	); err != nil {
		log.Printf("Failed to register xray log handler: %v", err)
	}
}

// --- PUBLIC API: INIT ---

// InitCoreEnv sets up asset/cert paths and the optional XUDP base key.
// envPath should point to the directory containing geoip.dat and geosite.dat.
func InitCoreEnv(envPath string, key string) {
	if envPath != "" {
		if err := os.Setenv("xray.location.asset", envPath); err != nil {
			log.Printf("Failed to set xray.location.asset: %v", err)
		}
		if err := os.Setenv("xray.location.cert", envPath); err != nil {
			log.Printf("Failed to set xray.location.cert: %v", err)
		}
	}
	if key != "" {
		if err := os.Setenv("xray.xudp.basekey", key); err != nil {
			log.Printf("Failed to set xray.xudp.basekey: %v", err)
		}
	}
	corefilesystem.NewFileReader = func(path string) (io.ReadCloser, error) {
		if _, err := os.Stat(path); os.IsNotExist(err) {
			_, file := filepath.Split(path)
			return mobasset.Open(file)
		}
		return os.Open(path)
	}
}

// RegisterLogListener routes xray-core runtime logs to the host application
// (e.g. Kotlin's log() → vpn_log.txt + Flutter UI). Pass nil to unregister.
func RegisterLogListener(l LogListener) {
	logListenerMu.Lock()
	logListener = l
	logListenerMu.Unlock()
}

// --- PUBLIC API: VPN PROTECTOR ---

// RegisterVpnProtector registers a socket protector called for every outbound
// socket xray-core opens. Call this before StartXray. Pass nil to unregister.
func RegisterVpnProtector(p VpnProtector) {
	if p == nil {
		setProtectFd(nil)
		internet.RegisterDialerController(nil)
		return
	}
	setProtectFd(func(fd int) { p.Protect(fd) })
	internet.RegisterDialerController(func(network, address string, conn syscall.RawConn) error {
		return conn.Control(func(fd uintptr) {
			p.Protect(int(fd))
		})
	})
}

// --- PUBLIC API: XRAY ---

// StartXray starts xray-core with the provided JSON config.
// If xray is already running it is stopped first, so the callback
// is always tied to the current call.
func StartXray(config string, cb XrayCallback) {
	StopXray()

	registerLogHandler()

	eng := &xrayEngine{cb: cb}
	xrayMu.Lock()
	xray = eng
	xrayMu.Unlock()

	go func() {
		eng.mu.Lock()
		defer eng.mu.Unlock()

		// StopXray could take eng.mu before this goroutine: it found no instance and
		// returned, so a core started now would be orphaned — never closed, holding
		// the SOCKS port and its upstream connections.
		if currentXray() != eng {
			if cb != nil {
				cb.OnStatus(-1, "start cancelled: core was stopped")
			}
			return
		}

		log.Println("[xray] initializing core...")
		cfg, err := coreserial.LoadJSONConfig(strings.NewReader(config))
		if err != nil {
			log.Printf("[xray] config error: %v", err)
			if cb != nil {
				cb.OnStatus(-1, fmt.Sprintf("config error: %v", err))
			}
			return
		}

		inst, err := core.New(cfg)
		if err != nil {
			log.Printf("[xray] core init failed: %v", err)
			if cb != nil {
				cb.OnStatus(-1, fmt.Sprintf("init failed: %v", err))
			}
			return
		}

		eng.statsManager, _ = inst.GetFeature(corestats.ManagerType()).(corestats.Manager)

		log.Println("[xray] starting core...")
		if err := inst.Start(); err != nil {
			log.Printf("[xray] startup failed: %v", err)
			if cb != nil {
				cb.OnStatus(-1, fmt.Sprintf("startup failed: %v", err))
			}
			return
		}

		eng.instance = inst
		eng.isRunning = true

		log.Println("[xray] started successfully")
		if cb != nil {
			cb.OnStatus(0, "Started successfully, running")
		}
	}()
}

// StopXray stops xray-core and releases all resources.
func StopXray() {
	xrayMu.Lock()
	eng := xray
	xray = nil
	xrayMu.Unlock()
	if eng == nil {
		return
	}

	eng.mu.Lock()
	defer eng.mu.Unlock()

	if eng.instance != nil {
		if err := eng.instance.Close(); err != nil {
			log.Printf("[xray] shutdown error: %v", err)
		}
		eng.instance = nil
	}
	eng.isRunning = false
	eng.statsManager = nil

	if eng.cb != nil {
		eng.cb.OnStatus(0, "Core stopped")
	}
}

// DumpGoroutines returns stack traces of all goroutines (diagnostics of hangs:
// xray, sing-box and tun2socks run in this process).
func DumpGoroutines() string {
	buf := make([]byte, 1<<20)
	for {
		n := runtime.Stack(buf, true)
		if n < len(buf) {
			return string(buf[:n])
		}
		buf = make([]byte, 2*len(buf))
	}
}

// GetXrayVersion returns the xray-core version string.
func GetXrayVersion() string {
	return fmt.Sprintf("xray-core v%s", core.Version())
}

// QueryXrayStats returns and resets the traffic counter for the given outbound
// tag and direction ("uplink" or "downlink").
func QueryXrayStats(tag string, direct string) int64 {
	eng := currentXray()
	if eng == nil {
		return 0
	}
	eng.mu.Lock()
	sm := eng.statsManager
	eng.mu.Unlock()

	if sm == nil {
		return 0
	}
	counter := sm.GetCounter(fmt.Sprintf("outbound>>>%s>>>traffic>>>%s", tag, direct))
	if counter == nil {
		return 0
	}
	return counter.Set(0)
}

// MeasureXrayDelay measures latency through the running xray instance.
// Returns milliseconds, or -1 on error.
func MeasureXrayDelay(url string) (int64, error) {
	eng := currentXray()
	if eng == nil {
		return -1, errors.New("xray not running")
	}
	eng.mu.Lock()
	inst := eng.instance
	eng.mu.Unlock()

	if inst == nil {
		return -1, errors.New("xray instance not ready")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 12*time.Second)
	defer cancel()
	return measureDelay(ctx, inst, url)
}

// MeasureOutboundDelay starts a temporary xray instance with the given config
// to measure latency without affecting the running session.
func MeasureOutboundDelay(config string, url string) (int64, error) {
	cfg, err := coreserial.LoadJSONConfig(strings.NewReader(config))
	if err != nil {
		return -1, fmt.Errorf("config load error: %w", err)
	}

	cfg.Inbound = nil
	var essential []*serial.TypedMessage
	for _, app := range cfg.App {
		switch app.Type {
		// No xray.app.log.Config: log.New registers the instance as the global
		// handler, and after Close the handler is inactive — the running VPN core
		// would stop logging until its next start.
		case "xray.app.proxyman.OutboundConfig",
			"xray.app.dispatcher.Config":
			essential = append(essential, app)
		}
	}
	cfg.App = essential

	inst, err := core.New(cfg)
	if err != nil {
		return -1, fmt.Errorf("instance creation failed: %w", err)
	}
	if err := inst.Start(); err != nil {
		return -1, fmt.Errorf("startup failed: %w", err)
	}
	defer inst.Close()
	return measureDelay(context.Background(), inst, url)
}

// RegisterXrayProcessFinder registers a per-app UID resolver for xray-core routing.
// Must be called after StartXray. Pass nil to unregister.
func RegisterXrayProcessFinder(finder ProcessFinder) {
	if finder == nil {
		corenet.RegisterAndroidProcessFinder(nil)
		return
	}
	corenet.RegisterAndroidProcessFinder(func(network, srcIP string, srcPort uint16, destIP string, destPort uint16) (uid int, name string, path string, err error) {
		if destPort == 0 || destIP == "" {
			return 0, "", "", fmt.Errorf("processFinder: no dest for %s %s:%d", network, srcIP, srcPort)
		}
		defer func() {
			if r := recover(); r != nil {
				uid, name, path, err = 0, "", "", fmt.Errorf("processFinder panic: %v", r)
			}
		}()
		uid = int(finder.FindProcessByConnection(network, srcIP, int64(srcPort), destIP, int64(destPort)))
		if uid < 0 {
			return 0, "", "", fmt.Errorf("processFinder: not found for %s %s:%d -> %s:%d", network, srcIP, srcPort, destIP, destPort)
		}
		return uid, fmt.Sprintf("%d", uid), "", nil
	})
}

// measureDelay measures HTTP round-trip latency through a running core instance.
func measureDelay(ctx context.Context, inst *core.Instance, url string) (int64, error) {
	return measureDelayVia(ctx, func(ctx context.Context, network, addr string) (net.Conn, error) {
		dest, err := corenet.ParseDestination(fmt.Sprintf("%s:%s", network, addr))
		if err != nil {
			return nil, err
		}
		return core.Dial(ctx, inst, dest)
	}, url)
}

// --- INTERNAL TUN2SOCKS WRAPPERS ---

type tunValidatorWrapper struct {
	validator TunValidator
}

func (w *tunValidatorWrapper) Validate(srcIP string, srcPort int, dstIP string, dstPort int, protocol int) bool {
	if w.validator == nil {
		return true
	}
	return w.validator.OnValidate(srcIP, int64(srcPort), dstIP, int64(dstPort), int64(protocol))
}

// --- PUBLIC API: TUN2SOCKS ---

// StartTun2Socks starts the TUN-to-SOCKS bridge.
//
//   - tunFD       — file descriptor from VpnService.establish()
//   - mtu         — MTU of the TUN interface; must match VpnService.Builder.setMtu()
//   - socksPort   — local port where xray-core listens for SOCKS5
//   - socksUser   — SOCKS5 username (empty = no auth)
//   - socksPass   — SOCKS5 password (empty = no auth)
//   - allowICMP   — allow ICMP echo (ping) through the tunnel
//   - blockQuic   — when true, intercept UDP/443 at the TUN level and reply with
//                   ICMP Port Unreachable. The packet never leaves the device; the
//                   browser sees the destination as unreachable for QUIC and falls
//                   back to TCP through the tunnel immediately, avoiding the ~55s
//                   QUIC handshake retransmission wait that silent dropping causes.
//   - validator   — per-connection allow/deny callback (nil = allow all)
//
// Returns an empty string on success, or an error message.
func StartTun2Socks(tunFD int64, mtu int64, socksPort int64, socksUser string, socksPass string, allowICMP bool, blockQuic bool, validator TunValidator) string {
	tun2socksMu.Lock()
	if tun2socksEngine == nil {
		tun2socksEngine = tun2socks.NewTeapodTun2socks()
	}
	eng := tun2socksEngine
	tun2socksMu.Unlock()

	v := &tunValidatorWrapper{validator: validator}
	return eng.Start(tunFD, mtu, "127.0.0.1", socksPort, socksUser, socksPass, allowICMP, blockQuic, 1000, 300, v)
}

// StopTun2Socks gracefully shuts down the TUN bridge.
func StopTun2Socks() {
	tun2socksMu.Lock()
	eng := tun2socksEngine
	tun2socksMu.Unlock()
	if eng != nil {
		eng.Stop()
	}
}

// IsTunRunning reports whether the TUN bridge is active.
func IsTunRunning() bool {
	tun2socksMu.Lock()
	eng := tun2socksEngine
	tun2socksMu.Unlock()
	return eng != nil && eng.IsRunning()
}

// TunActiveConnections returns the number of TCP connections currently being proxied
// through tun2socks. A sustained spike (e.g. >200) after hours of uptime indicates
// a gVisor connection leak that requires a reconnect.
func TunActiveConnections() int64 {
	tun2socksMu.Lock()
	eng := tun2socksEngine
	tun2socksMu.Unlock()
	if eng == nil {
		return 0
	}
	return eng.GetActiveConnections()
}

// GetTunStatsLine returns a diagnostic string with tunnel health metrics
// (active connections, gVisor TCP counters, channel queue depth, byte counters, cache size).
// Log it via Kotlin's log() so the line ends up in vpn_log.txt and the Flutter UI.
func GetTunStatsLine() string {
	tun2socksMu.Lock()
	eng := tun2socksEngine
	tun2socksMu.Unlock()
	if eng == nil {
		return ""
	}
	return eng.GetStatsLine()
}

// GetTunDiagnostics returns a JSON snapshot of the tunnel state (health metrics,
// failure counters, per-connection activity table). Empty string if not running.
func GetTunDiagnostics() string {
	tun2socksMu.Lock()
	eng := tun2socksEngine
	tun2socksMu.Unlock()
	if eng == nil {
		return ""
	}
	return eng.GetDiagnostics()
}

// GetTunCacheSize returns the number of entries in the validator's LRU cache.
func GetTunCacheSize() int64 {
	tun2socksMu.Lock()
	eng := tun2socksEngine
	tun2socksMu.Unlock()
	if eng == nil {
		return 0
	}
	return eng.CacheSize()
}

// SetTunLogEnabled toggles verbose logging inside the TUN bridge.
func SetTunLogEnabled(enabled bool) {
	tun2socksMu.Lock()
	eng := tun2socksEngine
	tun2socksMu.Unlock()
	if eng != nil {
		eng.SetLogEnabled(enabled)
	}
}

// GetTunUploadBytes returns total bytes sent from device to the internet.
func GetTunUploadBytes() int64 {
	tun2socksMu.Lock()
	eng := tun2socksEngine
	tun2socksMu.Unlock()
	if eng == nil {
		return 0
	}
	return eng.GetUploadBytes()
}

// GetTunDownloadBytes returns total bytes received from the internet to device.
func GetTunDownloadBytes() int64 {
	tun2socksMu.Lock()
	eng := tun2socksEngine
	tun2socksMu.Unlock()
	if eng == nil {
		return 0
	}
	return eng.GetDownloadBytes()
}

// GetTunLastRxActivityMs returns the Unix timestamp in milliseconds of the last
// successful write to the TUN interface (i.e. last time data reached the device).
// Returns 0 if tun2socks is not running or nothing has been written yet.
func GetTunLastRxActivityMs() int64 {
	tun2socksMu.Lock()
	eng := tun2socksEngine
	tun2socksMu.Unlock()
	if eng == nil {
		return 0
	}
	return eng.GetLastRxActivityMs()
}

// ForceTunCloseAllConnections closes all active proxied TCP connections in tun2socks.
// Apps receive a connection reset and reconnect through a clean gVisor path.
// Call on network-change events to prevent stale connections from surviving a
// physical network switch. Returns the number of connections closed.
func ForceTunCloseAllConnections() int64 {
	tun2socksMu.Lock()
	eng := tun2socksEngine
	tun2socksMu.Unlock()
	if eng == nil {
		return 0
	}
	return eng.ForceCloseAllConnections()
}
