# TeapodStream

VPN-клиент для Android с поддержкой протокола Xray и интерфейсом TUN.

## Возможности

- Поддержка протоколов: **VLESS**, **VMess**, **Trojan**, **Shadowsocks**
- Транспорты: **TCP**, **WebSocket**, **gRPC**, **H2**, **QUIC**
- Шифрование: **TLS**, **Reality**
- TUN-интерфейс — весь трафик устройства идёт через VPN
- Раздельное туннелирование — выбор приложений для исключения из VPN
- Подписки — автоматическое обновление конфигураций по URL
- QR-сканирование для быстрого добавления конфигураций
- Статистика трафика в реальном времени

## Архитектура

```
[Приложения] → [TUN-интерфейс] → [tun2socks] → [SOCKS5 127.0.0.1:port] → [xray-core] → [Удалённый сервер]
```

- **xray-core** — ядро маршрутизации (XTLS/Xray-core)
- **tun2socks** — мост между TUN-интерфейсом и SOCKS5-прокси xray
- **Android VpnService** — управление TUN-интерфейсом на уровне ОС

## Сборка

```bash
# Скачать бинарные зависимости (xray, tun2socks, geodata)
./build.sh binaries

# Debug APK
./build.sh debug

# Release APK (все архитектуры)
./build.sh release
```

### Требования

- Flutter SDK 3.11+
- Android SDK
- Java 21+

### Зависимости

Бинарные файлы загружаются автоматически при выполнении `./build.sh binaries`:
- [Xray-core](https://github.com/XTLS/Xray-core)
- [tun2socks](https://github.com/xjasonlyu/tun2socks)
- [geoip.dat](https://github.com/v2fly/geoip)
- [geosite.dat](https://github.com/v2fly/domain-list-community)

## Поддерживаемые архитектуры

- `arm64-v8a`
- `x86_64`

## Лицензия

Проект использует open-source компоненты:
- [Xray-core](https://github.com/XTLS/Xray-core) — MIT License
- [tun2socks](https://github.com/xjasonlyu/tun2socks) — Apache 2.0
