# teapod-core

Android VPN library that combines [xray-core](https://github.com/XTLS/Xray-core) and teapod-tun2socks (`tun2socks/`) into a single AAR compiled via [gomobile](https://pkg.go.dev/golang.org/x/mobile/cmd/gomobile).

## Cores

The fat AAR carries three independent VPN cores; the app picks one at runtime:

- **Go** — xray-core + teapod-tun2socks (gomobile, package `teapodcore`).
- **Rust** — [xray-rust](https://github.com/aimalygin/xray-rust) via the prebuilt
  [xray-rust-mobile](https://github.com/aimalygin/xray-rust-mobile) AAR
  (package `org.xrayrust.mobile`, `libxray_ffi.so` + `libxray_mobile_jni.so`).
  `build.sh` downloads the pinned version (`XRAY_RUST_VERSION`), verifies its
  SHA-256 and merges classes, proguard rules and the `arm64-v8a`/`x86_64`
  libraries into the fat AAR. License: MPL-2.0, see `third_party/xray-rust/`.
- **sing-box** — [sing-box](https://github.com/SagerNet/sing-box) v1.14.4 in the same
  gomobile bind (`StartBox`/`StopBox`, `MeasureBoxDelay`, `MeasureBoxOutboundDelay`),
  behind teapod-tun2socks like the Go core. Build tags: `TAGS` in `build.sh`
  (NaiveProxy links Cronet statically). License: GPL-3.0-or-later with an
  additional term on the name, see `third_party/sing-box/`.

ABIs: `arm64-v8a`, `x86_64` (armeabi-v7a is not built).

## Architecture

```
Android VpnService (Kotlin)
        │
        ├── Teapodcore.startXray()      — xray-core in-process (VLESS, VMess, Trojan, SS)
        └── Teapodcore.startTun2Socks() — TUN → SOCKS5 bridge with per-connection validation
```

Traffic flow: `TUN interface → tun2socks → xray-core SOCKS5 inbound → proxy outbound`

## Usage

```kotlin
import teapodcore.Teapodcore
import teapodcore.VpnProtector
import teapodcore.XrayCallback
import teapodcore.TunValidator

// 1. Set asset path (geoip.dat / geosite.dat)
Teapodcore.initCoreEnv(context.filesDir.absolutePath, "")

// 2. Protect xray sockets from routing through the VPN tunnel
Teapodcore.registerVpnProtector(object : VpnProtector {
    override fun protect(fd: Long): Boolean = vpnService.protect(fd.toInt())
})

// 3. Start xray-core with a JSON config
Teapodcore.startXray(configJson, object : XrayCallback {
    override fun onStatus(status: Long, message: String) {
        Log.d("VPN", "[xray] $message")
    }
})

// 4. Start TUN-to-SOCKS bridge
val tunFd = vpnBuilder.establish()
val error = Teapodcore.startTun2Socks(
    tunFd.fd.toLong(),
    socksPort    = 10808L,
    socksUser    = "",
    socksPass    = "",
    validator    = null   // null = allow all
)

// 5. Stop
Teapodcore.stopTun2Socks()
Teapodcore.stopXray()
```

### Split tunneling

Pass a `TunValidator` to `startTun2Socks` to filter connections by UID (requires API 29+):

```kotlin
val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

Teapodcore.startTun2Socks(fd, port, "", "", object : TunValidator {
    override fun onValidate(srcIP: String, srcPort: Long,
                            dstIP: String, dstPort: Long, protocol: Long): Boolean {
        val uid = cm.getConnectionOwnerUid(
            protocol.toInt(),
            InetSocketAddress(srcIP, srcPort.toInt()),
            InetSocketAddress(dstIP, dstPort.toInt())
        )
        return uid in allowedUids
    }
})
```

## API reference

| Function | Description |
|---|---|
| `initCoreEnv(path, xudpKey)` | Set asset directory and optional XUDP base key |
| `registerVpnProtector(p)` | Protect xray sockets via `VpnService.protect()` |
| `registerXrayProcessFinder(f)` | Enable UID-based routing rules in xray-core |
| `startXray(config, cb)` | Start xray-core with a JSON config string |
| `stopXray()` | Stop xray-core |
| `getXrayVersion()` | Returns the xray-core version string |
| `dumpGoroutines()` | Stack traces of all Go goroutines (hang diagnostics) |
| `queryXrayStats(tag, direction)` | Read and reset traffic counter for an outbound tag |
| `measureXrayDelay(url)` | Latency test through the running instance (ms) |
| `measureOutboundDelay(config, url)` | Latency test with a temporary instance |
| `startTun2Socks(fd, port, user, pass, validator)` | Start TUN bridge |
| `stopTun2Socks()` | Stop TUN bridge |
| `isTunRunning()` | Whether the TUN bridge is active |
| `getTunUploadBytes()` | Bytes sent from device to internet |
| `getTunDownloadBytes()` | Bytes received from internet to device |
| `getTunCacheSize()` | Validator LRU cache entry count |
| `setTunLogEnabled(enabled)` | Toggle verbose TUN logging |

## Building

This directory is part of the TeapodStream repository; the AAR is built from the repository root.

Requirements: Go (the version in `go.mod`), gomobile and gobind of the `golang.org/x/mobile` version in `go.mod`,
JDK, Android NDK 28.2.13676358 in `$ANDROID_HOME/ndk`.

```bash
m=$(awk '$1=="golang.org/x/mobile"{print $2}' go.mod)
go install "golang.org/x/mobile/cmd/gomobile@$m" "golang.org/x/mobile/cmd/gobind@$m"

../build.sh core        # build the fat AAR → ../android/app/libs/teapod-core.aar
./build.sh build        # the same, only into outputs/ (teapod-core.aar + per-ABI AARs)
./build.sh prepare      # only the patched xray-core in .xray-core/ — enough for go vet / go test
go test ./...
```

The AAR's identity is the git tree hash of `core/` (`git rev-parse --short=12 HEAD:core`): CI caches it by that hash,
and every app release carries it as `teapod-core-<hash>.aar`, which `../build.sh binaries` downloads instead of
building when the sources match.

`tun2socks/` is the TUN → SOCKS5 gateway (package `github.com/Wendor/teapod-core/tun2socks`), formerly the separate
teapod-tun2socks repository.

## License

[MIT](LICENSE) for this repository's own code. The built AAR links sing-box
(GPL-3.0-or-later), so a distributed binary is covered by the GPL.
