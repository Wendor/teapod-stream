# UidAwareTunForwarder — анализ, предложения и тестирование

## Содержание

1. [Описание проблемы](#описание-проблемы)
2. [Решение](#решение)
3. [Анализ реализации](#анализ-реализации)
   - [Сильные стороны](#сильные-стороны)
   - [Слабые стороны и ограничения](#слабые-стороны-и-ограничения)
4. [Предложения по улучшению](#предложения-по-улучшению)
5. [Step-by-step тестирование уязвимости](#step-by-step-тестирование-уязвимости)

---

## Описание проблемы

### SO_BINDTODEVICE bypass

Начиная с ядра Linux 5.7 (Android 11+), непривилегированные приложения могут использовать
`setsockopt(SO_BINDTODEVICE, "tun0")` для привязки сокета напрямую к TUN-интерфейсу VPN.

Это позволяет обходить механизм split tunneling VpnService:
- `addDisallowedApplication()` / `addAllowedApplication()` работают на уровне маршрутизации
- `SO_BINDTODEVICE` обходит маршрутизацию, инжектируя пакеты прямо в TUN
- tun2socks передаёт **все** пакеты без проверки — он «слепой» bridge
- Результат: вредоносное приложение может отправить трафик через VPN-туннель, минуя фильтрацию

Утилита `curl` демонстрирует это тривиально:
```bash
curl --interface tun0 http://ifconfig.co
```

### Почему tun2socks не защищает

tun2socks работает как userspace TCP/IP стек, который пересылает все пакеты из TUN fd
в SOCKS5-прокси. У него нет понятия UID (идентификатора приложения-отправителя).
Он не может отличить пакет от легитимного приложения от пакета, инжектированного через
`SO_BINDTODEVICE`.

---

## Решение

`UidAwareTunForwarder` — полная замена tun2socks, реализованная на Kotlin.

### Принцип работы

1. Чтение сырых IP-пакетов из TUN fd
2. Парсинг IP-заголовков (IPv4/IPv6) и транспортных заголовков (TCP/UDP)
3. Вызов `ConnectivityManager.getConnectionOwnerUid()` (API 29+) для определения UID приложения-отправителя
4. Если UID == -1 (неизвестен) — пакет **дропается** (SO_BINDTODEVICE bypass)
5. Разрешённые пакеты проксируются через SOCKS5 в xray-core

### Изменённые файлы

| Файл | Действие | Описание |
|------|----------|----------|
| `UidAwareTunForwarder.kt` | Новый | Userspace TCP/IP стек с UID-фильтрацией (~1380 строк) |
| `XrayVpnService.kt` | Изменён | Удалён tun2socks, интеграция UidAwareTunForwarder, добавлен onDestroy() |
| `build.gradle.kts` | Изменён | Добавлена зависимость kotlinx-coroutines-android:1.8.1 |

---

## Анализ реализации

### Сильные стороны

#### 1. Эффективная блокировка SO_BINDTODEVICE bypass
- `getConnectionOwnerUid()` возвращает -1 для пакетов, инъецированных через `SO_BINDTODEVICE`
- Все такие пакеты дропаются ещё до проксирования
- Подтверждено тестированием на реальном устройстве

#### 2. Полная TCP state machine
- Корректная обработка SYN → SYN-ACK → ESTABLISHED → FIN/RST
- Обработка all TCP edge cases: повторный SYN (пересоздание сессии), RST на несуществующую сессию, FIN с данными, FIN в обоих направлениях
- Отдельные состояния: SYN_RECEIVED, ESTABLISHED, CLOSE_WAIT, LAST_ACK, FIN_WAIT, CLOSED

#### 3. SOCKS5 с аутентификацией
- Поддержка RFC 1929 (username/password)
- Поддержка SOCKS5 CONNECT для TCP и UDP ASSOCIATE для UDP
- Корректный парсинг BND.ADDR (IPv4, IPv6, Domain)

#### 4. IPv4 + IPv6 поддержка
- Полный парсинг IPv4 и IPv6 заголовков
- Корректное построение пакетов для обеих версий
- Checksum: IPv4 header checksum + TCP/UDP pseudo-header checksum для обеих версий

#### 5. Асинхронная архитектура
- `CoroutineScope(Dispatchers.IO + SupervisorJob)` — отказ одной корутины не убивает остальные
- Неблокирующее подключение SOCKS5 — SYN-ACK отправляется устройству немедленно, SOCKS5 подключение в фоне
- Буферизация данных до готовности SOCKS5 (до 256 КБ)

#### 6. Защита от ресурсных утечек
- Graceful shutdown через `scope.cancel()` + закрытие всех сессий
- Session cleanup loop — TCP: 5 мин, UDP: 2 мин idle timeout
- `onDestroy()` добавлен в VpnService
- `AtomicBoolean running` предотвращает повторный start/stop

#### 7. MSS и Window Scale
- MSS TCP-опция в SYN-ACK (MTU - 40/60 байт)
- Window Scale = 6 для увеличения окна приёма
- Don't Fragment бит установлен в IPv4

#### 8. Защита от переполнения буфера
- `MAX_PENDING_BYTES = 256 КБ` — ограничение на буфер ожидания до подключения SOCKS
- При превышении — RST и закрытие сессии

#### 9. Адаптивное логирование
- Первые 5 дропов логируются всегда, затем каждый 500-й
- Предотвращает спам в logcat при массовой атаке

### Слабые стороны и ограничения

#### 1. Отсутствие TCP retransmission (Критично)
**Проблема:** Если пакет с данными от SOCKS потерян на пути в TUN (или устройство не подтвердило ACK), данные не будут повторно отправлены. Userspace стек просто отправляет данные и надеется, что они дойдут.

**Влияние:** На практике потеря пакетов TUN → device минимальна (это виртуальный интерфейс в пределах одного устройства), но при высокой нагрузке или медленном приложении-получателе возможны потери.

**Рекомендация:** Для production — реализовать таймер ретрансмиссии (как минимум простой RTO с удвоением).

#### 2. Отсутствие flow control / congestion control (Значимо)
**Проблема:** Окно приёма (Window) зашито в 65535 и не обновляется на основе реальной скорости потребления данных. Нет Slow Start, AIMD, или хотя бы sliding window.

**Влияние:** При быстром удалённом сервере и медленном приложении на устройстве — данные отправляются в TUN быстрее, чем приложение их читает. Это может привести к переполнению буферов ядра.

**Рекомендация:** Отслеживать ACK от устройства и уменьшать скорость отправки при отставании.

#### 3. Блокирующий I/O для TUN (Значимо)
**Проблема:** `FileInputStream.read()` — блокирующий вызов. Один корутин читает TUN в цикле, и при отсутствии данных он блокирует поток из IO dispatcher'а.

**Влияние:** Dispatchers.IO имеет по умолчанию 64 потока, так что один заблокированный поток не критичен. Но при большом количестве блокирующих сессий (SOCKS5 read loops тоже блокирующие) пул может исчерпаться.

**Рекомендация:** Рассмотреть NIO (`FileChannel` + `Selector`) или выделенный поток для TUN read.

#### 4. IPv6 extension headers не обрабатываются (Умеренно)
**Проблема:** `parseIPv6()` берёт `nextHeader` из фиксированного смещения (байт 6). Если присутствуют extension headers (Hop-by-Hop, Routing, Fragment и др.), `nextHeader` укажет на первый extension, а не на TCP/UDP.

**Влияние:** Пакеты с extension headers будут отброшены парсером. На практике в мобильных сетях extension headers редки для TCP/UDP.

**Рекомендация:** Добавить цепочку парсинга extension headers.

#### 5. Нет поддержки ICMP (Умеренно)
**Проблема:** ICMP/ICMPv6 пакеты полностью игнорируются. Не работают `ping`, `traceroute`, Path MTU Discovery.

**Влияние:** Диагностические инструменты не работают через VPN. Path MTU Discovery может влиять на производительность.

**Рекомендация:** Базовая поддержка ICMP Echo Request/Reply через raw socket.

#### 6. ISN (Initial Sequence Number) предсказуем (Незначительно)
**Проблема:** ISN генерируется через `AtomicInteger` с шагом 64000. Это предсказуемо и не соответствует RFC 6528 (рекомендация использования криптографической хеш-функции).

**Влияние:** В контексте TUN-интерфейса на том же устройстве предсказуемость ISN не является вектором атаки — злоумышленнику нужен доступ к TUN fd, что уже означает полный контроль.

**Рекомендация:** Низкий приоритет. Для соответствия стандартам — использовать `SecureRandom`.

#### 7. Нет TCP keepalive (Незначительно)
**Проблема:** Idle-сессии закрываются через 5-минутный timeout с RST, а не через TCP keepalive.

**Влияние:** Некоторые серверы ожидают keepalive для поддержания соединения. На практике большинство HTTP-клиентов на Android имеют свои keepalive-таймеры.

#### 8. Нет SACK (Selective Acknowledgment) (Незначительно)
**Проблема:** Без SACK при потере одного сегмента из серии придётся ретрансмитить всё начиная с потерянного.

**Влияние:** Низкое — потери в TUN минимальны (см. п.1).

#### 9. API 29+ ограничение
**Проблема:** `getConnectionOwnerUid()` доступен только на Android 10+. На более старых версиях UID-фильтрация пропускается (`Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q`).

**Влияние:** На Android < 10 SO_BINDTODEVICE всё равно недоступен непривилегированным приложениям (ядро < 5.7), поэтому уязвимость не актуальна.

#### 10. Однопоточное чтение TUN
**Проблема:** Один корутин на чтение всех пакетов из TUN. При высокой нагрузке обработка пакетов последовательна.

**Влияние:** Пропускная способность ограничена скоростью обработки одного потока. Для типичного мобильного использования достаточно.

---

## Предложения по улучшению

### Приоритет: Высокий

| # | Улучшение | Описание | Сложность |
|---|-----------|----------|-----------|
| 1 | TCP retransmission timer | Хранить отправленные но неподтверждённые сегменты, ретрансмитить по RTO | Высокая |
| 2 | Flow control | Отслеживать Window ACK от устройства, ограничивать скорость отправки | Средняя |
| 3 | Выделенный поток для TUN read | Заменить `Dispatchers.IO` на `newSingleThreadContext` для `tunReadLoop` | Низкая |

### Приоритет: Средний

| # | Улучшение | Описание | Сложность |
|---|-----------|----------|-----------|
| 4 | IPv6 extension headers | Цепочка next header → пропуск extension до TCP/UDP | Средняя |
| 5 | ICMP Echo passthrough | Проксирование ping через raw socket | Средняя |
| 6 | SOCKS5 connection pool | Переиспользование SOCKS5-соединений для снижения latency | Средняя |

### Приоритет: Низкий

| # | Улучшение | Описание | Сложность |
|---|-----------|----------|-----------|
| 7 | RFC 6528 ISN | Генерация ISN через MD5(src_ip, dst_ip, src_port, dst_port, secret_key) | Низкая |
| 8 | TCP keepalive | Отправка keepalive probes для idle TCP-сессий | Низкая |
| 9 | DNS-over-UDP оптимизация | Быстрый путь для DNS-запросов (порт 53) без полного UDP ASSOCIATE | Средняя |
| 10 | Метрики и статистика | Счётчики по UID: объём трафика, количество сессий, количество дропов | Низкая |

---

## Step-by-step тестирование уязвимости

### Предварительные требования

- Android-устройство с ядром 5.7+ (Android 11+)
- ADB-доступ к устройству (USB-отладка включена)
- Установленный TeapodStream APK
- Wi-Fi / мобильные данные (для реального VPN-подключения)
- Рабочий VPN-профиль (VLESS/VMess с валидным сервером)

### Шаг 1: Проверка версии ядра

```bash
adb shell uname -r
```

Ожидаемый вывод: `5.7.x` или выше (на практике Android 11+ обычно 5.4+, а SO_BINDTODEVICE для непривилегированных — с 5.7).

Если ядро < 5.7, SO_BINDTODEVICE для непривилегированных приложений недоступен, и уязвимость не воспроизводится.

### Шаг 2: Установка APK

```bash
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Если приложение уже запущено:
```bash
adb shell am force-stop com.teapodstream.teapodstream
```

### Шаг 3: Подключение VPN

1. Открыть TeapodStream на устройстве
2. Выбрать VPN-профиль
3. Нажать «Подключить»
4. Подтвердить VPN-разрешение (Android dialog)
5. Дождаться статуса «Подключено»

### Шаг 4: Проверка наличия TUN-интерфейса

```bash
adb shell ip addr show tun0
```

Ожидаемый вывод:
```
XX: tun0: <POINTOPOINT,UP,LOWER_UP> mtu 1500 ...
    inet 10.0.0.1/24 scope global tun0
```

### Шаг 5: Проверка нормальной работы VPN

```bash
adb shell curl -s --max-time 10 http://ifconfig.co
```

Ожидаемый вывод: IP-адрес VPN-сервера (не ваш реальный IP).

Это подтверждает, что VPN работает и трафик проксируется корректно.

### Шаг 6: Попытка bypass — SO_BINDTODEVICE через curl

```bash
adb shell curl -v --max-time 10 --interface tun0 http://ifconfig.co
```

Флаг `--interface tun0` заставляет curl использовать `SO_BINDTODEVICE` для привязки
сокета к TUN-интерфейсу напрямую, минуя routing table.

#### Ожидаемый результат С UidAwareTunForwarder (патч применён):

```
* Connected to ifconfig.co (104.21.54.91) port 80
* socket successfully bound to interface 'tun0'
* Connection timed out after 10002 milliseconds
* Closing connection
curl: (28) Connection timed out after 10002 milliseconds
```

TCP SYN-пакеты дропаются — соединение не устанавливается.

#### Ожидаемый результат БЕЗ патча (tun2socks):

```
* Connected to ifconfig.co (104.21.54.91) port 80
* socket successfully bound to interface 'tun0'
<реальный IP VPN-сервера>
```

Пакеты проходят через tun2socks → SOCKS5 → xray → интернет. Bypass успешен.

### Шаг 7: Проверка логов фильтрации

```bash
adb logcat -s TeapodStream --format=brief -d | grep "DROP"
```

Ожидаемый вывод (при применённом патче):
```
W/TeapodStream: DROP пакет (UID неизвестен): 10.0.0.1:XXXXX → 104.21.54.91:80 proto=6 [всего dropped=1]
W/TeapodStream: DROP пакет (UID неизвестен): 10.0.0.1:XXXXX → 104.21.54.91:80 proto=6 [всего dropped=2]
...
```

`proto=6` = TCP. Каждая строка — отдельный TCP SYN-retransmit, дропнутый форвардером.

### Шаг 8: Проверка UDP bypass (опционально)

```bash
adb shell nslookup google.com 1.1.1.1
```

Если DNS-запрос идёт через VPN — ответ должен прийти.
Для тестирования bypass по UDP нужен инструмент с поддержкой `SO_BINDTODEVICE` для UDP
(стандартные утилиты Android обычно этого не делают).

### Шаг 9: Массовый тест (стресс-тест)

```bash
for i in $(seq 1 20); do
  adb shell curl -s --max-time 3 --interface tun0 http://ifconfig.co &
done
wait
```

Все 20 соединений должны завершиться с timeout. В логах — рост счётчика dropped.

### Интерпретация результатов

| Сценарий | curl --interface tun0 | Логи DROP | Вердикт |
|----------|----------------------|-----------|---------|
| Патч применён, ядро 5.7+ | Connection timed out | Есть | ✅ Bypass заблокирован |
| Патч применён, ядро < 5.7 | Connection timed out / refused | - | ⚠️ SO_BINDTODEVICE недоступен, уязвимость не актуальна |
| Без патча (tun2socks), ядро 5.7+ | Показывает VPN IP | Нет | ❌ Bypass работает, уязвимость открыта |
| VPN выключен | Connection refused / Network unreachable | - | ℹ️ Нет TUN — нечего тестировать |

---

## Ссылки

- [SO_BINDTODEVICE unprivileged (kernel 5.7)](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=f9fbb3ad3e7d)
- [ConnectivityManager.getConnectionOwnerUid()](https://developer.android.com/reference/android/net/ConnectivityManager#getConnectionOwnerUid(int,%20java.net.InetSocketAddress,%20java.net.InetSocketAddress))
- [SOCKS5 RFC 1928](https://www.rfc-editor.org/rfc/rfc1928)
- [SOCKS5 Username/Password RFC 1929](https://www.rfc-editor.org/rfc/rfc1929)
- [Обсуждение уязвимости VPN на Android (Habr)](https://habr.com/)
