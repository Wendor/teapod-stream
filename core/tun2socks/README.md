# teapod-tun2socks — Strict AAR Library

**Русский** | [English](README.en.md)

Библиотека Android в формате AAR, которая работает как strict split-tunneling VPN-шлюз. Принимает FileDescriptor TUN-интерфейса, обрабатывает сырые IP-пакеты в TCP/UDP сессии через userspace TCP/IP стек (gvisor/netstack на Go), и строго проверяет UID процесса перед пересылкой трафика в SOCKS5 прокси.

## Использование в TeapodStream

[TeapodStream](https://github.com/Wendor/teapodstream) использует не этот AAR, а Go-пакет из `go/`: [teapod-core](https://github.com/Wendor/teapod-core) подключает его как модуль (`replace … => ../teapod-tun2socks/go` в `go.mod`) и собирает вместе с xray-core и sing-box в один fat AAR. Поэтому три репозитория клонируются рядом, а версия у них общая — `version` из `../teapodstream/pubspec.yaml` (меняется командой `./build.sh bump X.Y.Z` в teapodstream). Отдельный AAR из этого репозитория нужен только для использования библиотеки вне TeapodStream.

## Архитектура

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

## Принцип работы

1. **TUN → Go:** Android VpnService передаёт TUN FileDescriptor. Go-движок подключает его к gvisor netstack через `channel.Endpoint` — горутины читают/пишут пакеты напрямую через fd.

2. **Перехват соединений:** gvisor netstack перехватывает каждый новый TCP SYN и первый UDP пакет. Вызывается `EngineHook.Validate()`.

3. **UID валидация:**
   - Go вызывают Kotlin-коллбэк через gomobile JNI-мост
   - Kotlin использует `ConnectivityManager.getConnectionOwnerUid()` для определения UID
   - UID проверяется против whitelist (ALLOW_ONLY / DENY_ONLY режимы)
   - Результат возвращается синхронно в Go

4. **Решение:**
   - **Allowed (TCP):** соединение принимается, устанавливается SOCKS5 CONNECT, трафик пересылается через прокси
   - **Allowed (UDP):** устанавливается SOCKS5 UDP ASSOCIATE, датаграммы пересылаются через прокси-relay
   - **Denied (TCP):** RST отправляется обратно в TUN
   - **Denied (UDP):** пакет дропается

5. **Кеширование:** Результаты UID-проверки кешируются в LRU-кэше (10000 записей, TTL 5 минут) чтобы избежать JNI-вызовов для каждого пакета.

## Требования

| Компонент | Версия |
|-----------|--------|
| Android API | 29+ (Android Q) |
| Go | 1.25.5+ (`go/go.mod`) |
| gomobile | latest |
| Android NDK | r28 (как в teapod-core) |
| JDK | 17+ (AGP 8.7; CI использует 21), байткод библиотеки — Java 8 |

## Сборка

### 1. Установка зависимостей

```bash
# Установите Go (если не установлен)
brew install go

# Установите gomobile
go install golang.org/x/mobile/cmd/gomobile@latest
go install golang.org/x/mobile/cmd/gobind@latest

# Инициализируйте gomobile
gomobile init

# Убедитесь что NDK доступен
export ANDROID_NDK_HOME=$HOME/Android/Sdk/ndk/<version>
```

### 2. Компиляция AAR

```bash
# Собрать все архитектуры (arm64-v8a, armeabi-v7a, x86_64)
./build.sh

# Собрать только для arm64
./build.sh arm64

# Очистить выходные файлы
./build.sh clean
```

### 3. Результат

После завершения сборки в директории `output/` будут созданы следующие файлы (где `1.0.0` — общая версия проекта из `../teapodstream/pubspec.yaml`, передаётся в Gradle как `-PlibraryVersion`):
- `teapod-tun2socks-arm64-v8a-1.0.0.aar` — AAR для arm64-v8a.
- `teapod-tun2socks-armeabi-v7a-1.0.0.aar` — AAR для armeabi-v7a.
- `teapod-tun2socks-x86_64-1.0.0.aar` — AAR для x86_64.
- `teapod-tun2socks-sources.jar` — исходники для IDE.

### 4. Go unit-тесты

```bash
cd go/
GOOS=linux GOARCH=amd64 go test -v ./...
```

### 5. Сборка Kotlin-обёртки (AAR)

```bash
# Сначала соберите Go AAR
./build.sh

# Затем соберите Kotlin-обёртку
cd kotlin/
./gradlew assembleRelease
```

Kotlin AAR будет в `kotlin/build/outputs/aar/`.

## Интеграция в Android-проект

### 1. Добавьте AAR в проект

Поместите `teapod-tun2socks.aar` в `app/libs/`:

```
app/
├── libs/
│   └── teapod-tun2socks.aar
└── build.gradle
```

### 2. Подключите в build.gradle

```gradle
dependencies {
    implementation(files("libs/teapod-tun2socks.aar"))
}
```

### 3. Добавьте разрешения в AndroidManifest.xml

```xml
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
```

## Использование

### Базовый пример

```kotlin
import com.teapodstream.tun2socks.TeapodVpnManager
import com.teapodstream.tun2socks.WhitelistMode

class MyVpnService : VpnService() {

    private lateinit var teapodVpnManager: TeapodVpnManager

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // 1. Настройте TUN-интерфейс
        val tunFd = setupTunnel()

        // 2. Создайте менеджер
        teapodVpnManager = TeapodVpnManager(this)

        // 3. Запустите teapod-tun2socks
        teapodVpnManager.start(
            tunFd = tunFd,
            socksHost = "proxy.example.com",
            socksPort = 1080,
            socksUsername = "myuser",
            socksPassword = "mypass",
            // Разрешить ТОЛЬКО эти UID
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
            ?: throw IllegalStateException("Не удалось создать TUN-интерфейс")
    }
}
```

### Продвинутое использование с кастомным валидатором

```kotlin
// Дополнительная валидация помимо UID
val customValidator = UidValidator { srcAddr, srcPort, dstAddr, dstPort, protocol ->
    // Например, блокировать соединения с определёнными IP
    if (dstAddr == "192.168.1.100") {
        return@UidValidator false
    }
    // Разрешить остальные
    true
}

teapodVpnManager.start(
    tunFd = tunFd,
    socksHost = "proxy.example.com",
    socksPort = 1080,
    allowedUids = setOf(10086, 10087, 10088),
    whitelistMode = WhitelistMode.ALLOW_ONLY,
    cacheCapacity = 50000,       // Увеличить кэш
    cacheTtlSeconds = 600,      // TTL 10 минут
    customValidator = customValidator
)
```

### Режимы whitelist

| Режим | Поведение |
|-------|-----------|
| `ALLOW_ONLY` | Разрешать ТОЛЬКО UID из списка. Все остальные блокируются. |
| `DENY_ONLY` | Блокировать ТОЛЬКО UID из списка. Все остальные разрешены. |
| `ALLOW_ALL` | Разрешать все соединения (режим отладки). |

### Отладка

```kotlin
// Включить логи Go-слоя
teapodVpnManager.setDebugLogging(true)

// Проверить статус
Log.d("VPN", "Running: ${teapodVpnManager.isRunning()}")
Log.d("VPN", "Cache size: ${teapodVpnManager.getCacheSize()}")
```

## Структура проекта

```
teapod-tun2socks/
├── go/                          # Go-код (gomobile bind)
│   ├── go.mod                   # Go module + зависимости
│   ├── go.sum                   # Lock-файл зависимостей
│   ├── teapod_tun2socks.go      # Точка входа для gomobile (экспорт в Kotlin)
│   ├── engine.go                # Движок TUN → SOCKS5 (gvisor netstack)
│   ├── engine_hook.go           # Хук UID-валидации + LRU-кэш
│   ├── connection.go            # Модель соединения + LRU-кэш
│   ├── socks5.go                # SOCKS5 клиент (CONNECT + UDP ASSOCIATE)
│   └── icmp_reject.go           # ICMP «порт недоступен» для отклонённого UDP
│
├── kotlin/src/main/java/com/teapodstream/tun2socks/
│   ├── TeapodVpnManager.kt      # Публичный API менеджер
│   ├── UidValidator.kt          # Интерфейс пользовательского валидатора
│   ├── UidResolver.kt           # Обёртка над getConnectionOwnerUid
│   └── TeapodTun2socksCallback.kt # JNI-мост Go ↔ Kotlin
│
├── build.sh                     # Скрипт сборки
├── README.en.md                 # README на английском
└── README.md                    # Этот файл
```

## API Reference

### TeapodVpnManager

| Метод | Описание |
|-------|----------|
| `start(tunFd, socksHost, socksPort, ...)` | Запустить teapod-tun2socks |
| `stop()` | Остановить teapod-tun2socks (блокируется до завершения) |
| `isRunning(): Boolean` | Проверить статус |
| `getCacheSize(): Int` | Размер кэша UID-валидаций |
| `setDebugLogging(enabled: Boolean)` | Включить/выключить логи Go |

### UidValidator (интерфейс)

```kotlin
interface UidValidator {
    fun validate(
        srcAddr: String,
        srcPort: Int,
        dstAddr: String,
        dstPort: Int,
        protocol: Int  // OsConstants.IPPROTO_TCP (6) или IPPROTO_UDP (17)
    ): Boolean
}
```

## Troubleshooting

### "teapod-tun2socks already started"

Вызовите `stop()` перед повторным `start()`.

### "engine creation failed: dup tunFD: ..."

Убедитесь что TUN FileDescriptor валиден и получен из `VpnService.Builder.establish()`.

### UID всегда -1

- Проверьте что вызывается `getConnectionOwnerUid` на API 29+
- Убедитесь что `ACCESS_NETWORK_STATE` разрешение предоставлено
- Соединение должно быть активно в момент вызова

### gomobile bind fails with "missing go.sum"

```bash
cd go/
go mod tidy
```

```bash
export ANDROID_NDK_HOME=$HOME/Android/Sdk/ndk/<version>
# или через Android Studio: Tools → SDK Manager → SDK Tools → NDK
```

## Лицензия

MIT
