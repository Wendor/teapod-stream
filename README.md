# TeapodStream

VPN-клиент для Android с поддержкой протокола Xray и интерфейсом TUN.

## Возможности

- Протоколы: **VLESS**, **VMess**, **Trojan**, **Shadowsocks**
- Транспорты: **TCP**, **WebSocket**, **gRPC**, **H2**, **QUIC**, **xHTTP**, **HTTPUpgrade**, **SplitHTTP**
- Шифрование: **TLS**, **Reality** (включая post-quantum ML-DSA-65)
- Shadowsocks prefix proxy — обход DPI для серверов с параметром `?prefix=`
- TUN-интерфейс — весь трафик устройства идёт через VPN
- Режим «только прокси» — запуск SOCKS5-прокси без поднятия TUN-туннеля
- Раздельное туннелирование — исключение или включение конкретных приложений
- Подписки — автоматическое обновление конфигураций по URL (включая self-signed TLS)
- QR-сканирование для быстрого добавления конфигураций
- Статистика трафика в реальном времени

## Архитектура

Режим TUN (по умолчанию):
```
[Приложения] → [TUN-интерфейс] → [teapod-tun2socks] → [SOCKS5 127.0.0.1:port] → [xray-core] → [Сервер]
```

Режим «только прокси»:
```
[Приложение] → [SOCKS5 127.0.0.1:port] → [xray-core] → [Сервер]
```

- **xray-core** — ядро маршрутизации (XTLS/Xray-core)
- **teapod-tun2socks** — мост между TUN-интерфейсом и SOCKS5-прокси xray (AAR)
- **Android VpnService** — управление TUN-интерфейсом на уровне ОС

## Настройки

### Xray

| Параметр | По умолчанию | Описание |
|---|---|---|
| Случайный порт | выкл | Случайный SOCKS5-порт при каждом подключении |
| SOCKS5 порт | 10808 | Фиксированный порт (когда случайный выкл) |
| Случайные учётные данные | вкл | Генерировать логин/пароль SOCKS при каждом подключении |
| Логин / Пароль SOCKS | — | Фиксированные учётные данные (можно оставить пустыми — прокси без аутентификации) |
| Только прокси | выкл | Запустить только SOCKS5-прокси без VPN-туннеля (разрешения на VPN не требуется) |
| UDP | вкл | Пропускать UDP-трафик через SOCKS |
| Режим DNS | Через VPN | Маршрутизация DNS-запросов |

### Подписки

- Поддержка base64 и plain-text форматов
- Подписки с self-signed TLS-сертификатами: приложение показывает диалог с информацией о сертификате и предлагает продолжить
- HTTP User-Agent: `TeapodStream/<версия> (Android; XrayNG-compatible) Xray-core/<версия>`

## Сборка

```bash
# Скачать бинарные зависимости (xray, geodata)
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
- [geoip.dat](https://github.com/v2fly/geoip)
- [geosite.dat](https://github.com/v2fly/domain-list-community)

AAR-зависимости подключаются через Gradle:
- [teapod-tun2socks](https://github.com/Wendor/teapod-tun2socks)

## Поддерживаемые архитектуры

- `arm64-v8a`
- `x86_64`

## Лицензия

Проект использует open-source компоненты:
- [Xray-core](https://github.com/XTLS/Xray-core) — MIT License
- [teapod-tun2socks](https://github.com/Wendor/teapod-tun2socks) — MIT License
