# teapod-tun2socks — Strict AAR Library

[Русский](README.md) | **English**

An Android AAR library that works as a strict split-tunneling VPN gateway. It takes the TUN interface FileDescriptor, turns raw IP packets into TCP/UDP sessions with a userspace TCP/IP stack (gvisor/netstack in Go), and strictly checks the process UID before forwarding traffic to a SOCKS5 proxy.

## Use in TeapodStream

[TeapodStream](https://github.com/Wendor/teapodstream) doesn't use this AAR but the Go package from `go/`: [teapod-core](https://github.com/Wendor/teapod-core) pulls it in as a module (`replace … => ../teapod-tun2socks/go` in `go.mod`) and builds it together with xray-core and sing-box into a single fat AAR. That's why the three repositories are cloned side by side and share one version — `version` from `../teapodstream/pubspec.yaml` (changed with `./build.sh bump X.Y.Z` in teapodstream). The standalone AAR from this repository is only needed to use the library outside TeapodStream.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Android VpnService                     │
│  ┌────────────────────────┐                             │
│  │ TUN Interface          │──────┐                      │
│  │ (ParcelFileDescriptor) │      │                      │
│  └────────────────────────┘      │                      │
└──────────────────────────────────┼──────────────────────┘
                                   ▼
┌──────────────────────────────────────────────────────────┐
│              Kotlin Layer (AAR)                          │
│           com.teapodstream.tun2socks                     │
│                                                          │
│  ┌──────────────────────┐   ┌────────────────────────┐   │
│  │ TeapodVpnManager     │──▶│ UidResolver            │   │
│  │ (public API)         │   │ (getConnectionOwnerUid)│   │
│  └──────────────────────┘   └────────────────────────┘   │
│           │                        │                     │
│           ▼                        ▼                     │
│  ┌──────────────────────┐   ┌─────────────────────┐      │
│  │ TeapodTun2socksCall  │◀──│ Whitelist (UID set) │      │
│  │ (gomobile interface) │   │                     │      │
│  └──────────────────────┘   └─────────────────────┘      │
└───────────────────────────┼──────────────────────────────┘
                            │ gomobile bind (JNI)
                            ▼
┌─────────────────────────────────────────────────────────┐
│                  Go Layer (Native .so)                  │
│              github.com/teapodstream/tun2socks          │
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │ TeapodTun2   │  │ EngineHook   │  │ LRU Cache    │   │
│  │ (entrypoint) │─▶│ (validation) │─▶│ (10k entries)│   │
│  └──────────────┘  └──────────────┘  └──────────────┘   │
│         │                                               │
│         ▼                                               │
│  ┌──────────────────────────────────────────────────┐   │
│  │          gvisor/netstack (userspace TCP/IP)      │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────────────┐   │   │
│  │  │  TCP    │  │  UDP    │  │ Packet Parser   │   │   │
│  │  │Forwarder│  │Forwarder│  │ (IPv4/IPv6)     │   │   │
│  │  └────┬────┘  └────┬────┘  └─────────────────┘   │   │
│  │       │            │                             │   │
│  │       ▼            ▼                             │   │
│  │  ┌─────────────────────────────┐                 │   │
│  │  │     SOCKS5 Client           │                 │   │
│  │  │  (TCP: CONNECT,             │                 │   │
│  │  │   UDP: UDP ASSOCIATE)       │                 │   │
│  │  └─────────────────────────────┘                 │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

## How it works

1. **TUN → Go:** Android VpnService passes the TUN FileDescriptor. The Go engine attaches it to gvisor netstack via `channel.Endpoint` — goroutines read/write packets directly through the fd.

2. **Connection interception:** gvisor netstack intercepts every new TCP SYN and the first UDP packet. `EngineHook.Validate()` is called.

3. **UID validation:**
   - Go calls a Kotlin callback through the gomobile JNI bridge
   - Kotlin uses `ConnectivityManager.getConnectionOwnerUid()` to determine the UID
   - The UID is checked against the whitelist (ALLOW_ONLY / DENY_ONLY modes)
   - The result is returned synchronously to Go

4. **Decision:**
   - **Allowed (TCP):** the connection is accepted, a SOCKS5 CONNECT is established, traffic is forwarded through the proxy
   - **Allowed (UDP):** a SOCKS5 UDP ASSOCIATE is established, datagrams are forwarded through the proxy relay
   - **Denied (TCP):** an RST is sent back into TUN
   - **Denied (UDP):** the packet is dropped

5. **Caching:** UID check results are cached in an LRU cache (10000 entries, 5-minute TTL) to avoid JNI calls for every packet.

## Requirements

| Component | Version |
|-----------|--------|
| Android API | 29+ (Android Q) |
| Go | 1.25.5+ (`go/go.mod`) |
| gomobile | latest |
| Android NDK | r28 (same as teapod-core) |
| JDK | 17+ (AGP 8.7; CI uses 21), library bytecode — Java 8 |

## Building

### 1. Installing dependencies

```bash
# Install Go (if not installed)
brew install go

# Install gomobile
go install golang.org/x/mobile/cmd/gomobile@latest
go install golang.org/x/mobile/cmd/gobind@latest

# Initialize gomobile
gomobile init

# Make sure the NDK is available
export ANDROID_NDK_HOME=$HOME/Android/Sdk/ndk/<version>
```

### 2. Compiling the AAR

```bash
# Build all architectures (arm64-v8a, armeabi-v7a, x86_64)
./build.sh

# Build arm64 only
./build.sh arm64

# Clean output files
./build.sh clean
```

### 3. Output

After the build the `output/` directory contains the following files (where `1.0.0` is the shared project version from `../teapodstream/pubspec.yaml`, passed to Gradle as `-PlibraryVersion`):
- `teapod-tun2socks-arm64-v8a-1.0.0.aar` — AAR for arm64-v8a.
- `teapod-tun2socks-armeabi-v7a-1.0.0.aar` — AAR for armeabi-v7a.
- `teapod-tun2socks-x86_64-1.0.0.aar` — AAR for x86_64.
- `teapod-tun2socks-sources.jar` — sources for the IDE.

### 4. Go unit tests

```bash
cd go/
GOOS=linux GOARCH=amd64 go test -v ./...
```

### 5. Building the Kotlin wrapper (AAR)

```bash
# Build the Go AAR first
./build.sh

# Then build the Kotlin wrapper
cd kotlin/
./gradlew assembleRelease
```

The Kotlin AAR ends up in `kotlin/build/outputs/aar/`.

## Integrating into an Android project

### 1. Add the AAR to the project

Put `teapod-tun2socks.aar` into `app/libs/`:

```
app/
├── libs/
│   └── teapod-tun2socks.aar
└── build.gradle
```

### 2. Add it to build.gradle

```gradle
dependencies {
    implementation(files("libs/teapod-tun2socks.aar"))
}
```

### 3. Add permissions to AndroidManifest.xml

```xml
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
```

## Usage

### Basic example

```kotlin
import com.teapodstream.tun2socks.TeapodVpnManager
import com.teapodstream.tun2socks.WhitelistMode

class MyVpnService : VpnService() {

    private lateinit var teapodVpnManager: TeapodVpnManager

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // 1. Set up the TUN interface
        val tunFd = setupTunnel()

        // 2. Create the manager
        teapodVpnManager = TeapodVpnManager(this)

        // 3. Start teapod-tun2socks
        teapodVpnManager.start(
            tunFd = tunFd,
            socksHost = "proxy.example.com",
            socksPort = 1080,
            socksUsername = "myuser",
            socksPassword = "mypass",
            // Allow ONLY these UIDs
            allowedUids = setOf(10086, 10087),
            whitelistMode = WhitelistMode.ALLOW_ONLY
        )

        return START_STICKY
    }

    override fun onDestroy() {
        teapodVpnManager.stop()
        super.onDestroy()
    }

    private fun setupTunnel(): ParcelFileDescriptor {
        return Builder()
            .addAddress("10.0.0.2", 32)
            .addRoute("0.0.0.0", 0)
            .addDnsServer("8.8.8.8")
            .establish()
            ?: throw IllegalStateException("Failed to create the TUN interface")
    }
}
```

### Advanced usage with a custom validator

```kotlin
// Extra validation besides the UID
val customValidator = UidValidator { srcAddr, srcPort, dstAddr, dstPort, protocol ->
    // E.g. block connections to specific IPs
    if (dstAddr == "192.168.1.100") {
        return@UidValidator false
    }
    // Allow the rest
    true
}

teapodVpnManager.start(
    tunFd = tunFd,
    socksHost = "proxy.example.com",
    socksPort = 1080,
    allowedUids = setOf(10086, 10087, 10088),
    whitelistMode = WhitelistMode.ALLOW_ONLY,
    cacheCapacity = 50000,       // Bigger cache
    cacheTtlSeconds = 600,      // 10-minute TTL
    customValidator = customValidator
)
```

### Whitelist modes

| Mode | Behavior |
|-------|-----------|
| `ALLOW_ONLY` | Allow ONLY the listed UIDs. Everything else is blocked. |
| `DENY_ONLY` | Block ONLY the listed UIDs. Everything else is allowed. |
| `ALLOW_ALL` | Allow all connections (debug mode). |

### Debugging

```kotlin
// Enable Go layer logs
teapodVpnManager.setDebugLogging(true)

// Check the status
Log.d("VPN", "Running: ${teapodVpnManager.isRunning()}")
Log.d("VPN", "Cache size: ${teapodVpnManager.getCacheSize()}")
```

## Project layout

```
teapod-tun2socks/
├── go/                          # Go code (gomobile bind)
│   ├── go.mod                   # Go module + dependencies
│   ├── go.sum                   # Dependency lock file
│   ├── teapod_tun2socks.go      # gomobile entry point (exported to Kotlin)
│   ├── engine.go                # TUN → SOCKS5 engine (gvisor netstack)
│   ├── engine_hook.go           # UID validation hook + LRU cache
│   ├── connection.go            # Connection model + LRU cache
│   ├── socks5.go                # SOCKS5 client (CONNECT + UDP ASSOCIATE)
│   └── icmp_reject.go           # ICMP "port unreachable" for rejected UDP
│
├── kotlin/src/main/java/com/teapodstream/tun2socks/
│   ├── TeapodVpnManager.kt      # Public API manager
│   ├── UidValidator.kt          # Custom validator interface
│   ├── UidResolver.kt           # Wrapper over getConnectionOwnerUid
│   └── TeapodTun2socksCallback.kt # Go ↔ Kotlin JNI bridge
│
├── build.sh                     # Build script
├── README.md                    # README in Russian
└── README.en.md                 # This file
```

## API Reference

### TeapodVpnManager

| Method | Description |
|-------|----------|
| `start(tunFd, socksHost, socksPort, ...)` | Start teapod-tun2socks |
| `stop()` | Stop teapod-tun2socks (blocks until finished) |
| `isRunning(): Boolean` | Check the status |
| `getCacheSize(): Int` | UID validation cache size |
| `setDebugLogging(enabled: Boolean)` | Enable/disable Go logs |

### UidValidator (interface)

```kotlin
interface UidValidator {
    fun validate(
        srcAddr: String,
        srcPort: Int,
        dstAddr: String,
        dstPort: Int,
        protocol: Int  // OsConstants.IPPROTO_TCP (6) or IPPROTO_UDP (17)
    ): Boolean
}
```

## Troubleshooting

### "teapod-tun2socks already started"

Call `stop()` before calling `start()` again.

### "engine creation failed: dup tunFD: ..."

Make sure the TUN FileDescriptor is valid and comes from `VpnService.Builder.establish()`.

### UID is always -1

- Check that `getConnectionOwnerUid` is called on API 29+
- Make sure the `ACCESS_NETWORK_STATE` permission is granted
- The connection must be active at the time of the call

### gomobile bind fails with "missing go.sum"

```bash
cd go/
go mod tidy
```

```bash
export ANDROID_NDK_HOME=$HOME/Android/Sdk/ndk/<version>
# or via Android Studio: Tools → SDK Manager → SDK Tools → NDK
```

## License

MIT
