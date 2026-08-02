# Реиспользование TUN fd при auto-reconnect + probe перед reconnect на wake

**Дата:** 2026-07-17
**Контекст:** issue #81, комментарий Hobbix — на Android 16 системное уведомление «Сеть VPN активна» всплывает при каждом фоновом `reconnectInternal()`, т.к. реконнект делает новый `builder.establish()`. Отвалы туннеля побеждены фиксами в tun2socks (UDP-утечка, read-error→Stop, ForceCloseAllConnections), а не пересозданием TUN — пересоздание при auto-reconnect не нужно.

## Проблема

`reconnectInternal()` → `stopVpn(reconnecting=true)` → `ACTION_CONNECT_QUICK` → `startVpn(isReconnect=true)` → `builder.establish()`. Каждый `establish()` регистрирует новый VPN network agent → Android 15/16 постит системное уведомление заново. Плюс connectivity-флап для приложений и 3-5с обрыва. Watchdog `checkTunStallOnWake()` усугубляет: реконнектит вслепую по «TUN idle ≥ 120с» на живом туннеле.

## Решение

### A. Реиспользование TUN fd в auto-reconnect

TUN нужно пересоздавать только при смене параметров `Builder` (MTU, split tunnel, IPv6, маршруты). Все параметры `ACTION_CONNECT_QUICK` читаются из `ConnectionParams` на диске — те же, с которыми установлен текущий TUN (смена настроек идёт через явный disconnect+connect из UI). Значит на пути auto-reconnect fd реиспользуем всегда, когда он жив.

Технически возможно без изменений teapod-core: tun2socks работает на dup'нутом fd (`teapod-tun2socks/go/engine.go:220`, `unix.Dup`), `StopTun2Socks()` закрывает только свой dup — оригинальный `ParcelFileDescriptor` остаётся валидным.

**Изменения в `XrayVpnService.kt`:**

1. **`stopVpn(reconnecting=true)`** — держать TUN открытым всегда, не только при kill switch:
   `keepTunAsSink = (killSwitchEnabled || reconnecting) && !explicit && !proxyOnlyMode && tunInterface != null`.
   Побочный эффект: у пользователей без kill switch трафик во время реконнекта блокируется TUN-sink вместо утечки в обход VPN — это улучшение.

2. **`startVpn(isReconnect=true)`** — ветка реиспользования: если `previousTun != null && !proxyOnly` — пропустить Builder/`establish()`, `tunInterface = previousTun; previousTun = null` (обнуление сразу, чтобы catch-блок не закрыл активный fd). Xray и tun2socks стартуют как раньше, `StartTun2Socks` получает тот же fd. Если `previousTun == null` (рестарт процесса системой, первый connect) — полный establish, как сейчас.

3. **Catch-блок `startVpn`:** логика восстановления sink не меняется; при реиспользовании `previousTun` уже null → закрытие-noop, fd остаётся в `tunInterface` и переживает retry-цикл через `stopVpn(reconnecting=true)`.

Пользовательский `ACTION_CONNECT` — всегда полный establish (уведомление там уместно и параметры могли смениться).

### B. Probe перед реконнектом в `checkTunStallOnWake()`

Вместо слепого `reconnectInternal()` при `idle ≥ 120с`: daemon-поток (onReceive — main thread) выполняет `checkTunnelConnectivity(activeSocksPort)` (SOCKS5 → cp.cloudflare.com через xray, soTimeout 10с — проверяет именно upstream-сессию, которая и протухает после Doze):

- probe OK → `log info "TUN idle Ns but tunnel alive, skipping reconnect"`, реконнекта нет;
- probe fail → `log warning` + `reconnectInternal()` (исходный кейс stale-after-Doze покрыт).

Защита от параллельных probe — `AtomicBoolean`. Периодический stall-детект в heartbeat-цикле (`activeConns >= 2`) не меняется.

## Что не делаем

- Раздельный рестарт «только xray» — лишний кодовый путь, не лечит утечку gVisor, экономия мизерная.
- Удаление watchdog'ов — с A их срабатывания становятся невидимыми (нет уведомления, нет флапа), риск false positive приемлем.
- Изменения teapod-core/teapod-tun2socks — не требуются.

## Верификация

Unit-тестов для нативного слоя нет — проверка на устройстве:
1. Debug-сборка, подключение, искусственный реконнект (смена WiFi→LTE) → в шторке нет нового «Сеть VPN активна», в логе `reconnectInternal` без `TUN established`.
2. Блокировка телефона 5+ мин → wake → в логе probe-результат, реконнект только при провале.
3. Явный disconnect/connect из UI → полный establish, уведомление одно.
4. Kill switch: обрыв при включённом — состояние `blocked`, TUN-sink держит трафик.

## Wiki

Обновить `wiki/components/android_native.md` (reconnect flow, fd reuse, wake-probe) + запись в `wiki/log.md`.
