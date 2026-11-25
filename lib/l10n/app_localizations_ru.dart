// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get tabConfigs => 'Конфиги';

  @override
  String get tabRouting => 'Маршрут';

  @override
  String get tabSettings => 'Настройки';

  @override
  String get homeNoConfigShort => 'нет конфига';

  @override
  String get homeUnsupported => 'не поддерживается';

  @override
  String get homeNoConfig => 'нет конфигурации';

  @override
  String get homeLogs => 'логи';

  @override
  String homeTunnel(String proto) {
    return 'ТУННЕЛЬ · $proto';
  }

  @override
  String get homeKillSwitchBlocked => 'kill switch · трафик заблокирован';

  @override
  String get homeConnectError => 'ошибка подключения';

  @override
  String get homeTapToRetry => 'нажмите для повтора';

  @override
  String get homeConnecting => 'установка соединения…';

  @override
  String get homeDisconnecting => 'завершение сеанса…';

  @override
  String get homeNoConfigAdd => 'нет конфигурации — добавьте';

  @override
  String get homeTapToConnect => 'нажмите для подключения';

  @override
  String get homeIpUnknown => 'IP не определён';

  @override
  String get homeDisconnectButton => 'ОТКЛЮЧИТЬ';

  @override
  String get homeActionReconnect => 'переподключить';

  @override
  String get homeActionDisconnect => 'отключить';

  @override
  String get homeActionWait => 'ожидание';

  @override
  String get homeActionConnect => 'подключить';

  @override
  String get homeChangeServer => 'сменить сервер';

  @override
  String get homeServer => 'Сервер';

  @override
  String get homePing => 'Пинг';

  @override
  String get homeUpload => 'Отдача';

  @override
  String get homeDownload => 'Загрузка';

  @override
  String get homeCoreEnableHint => 'включите ядро в настройках или смените конфиг';

  @override
  String get homeCorePinned => 'закреплено';

  @override
  String get homeManagedOnlySelected =>
      'режим «Только» по доменам и DNS-настройки не применяются · роутинг управляется сервером';

  @override
  String get homeManagedDns => 'DNS-настройки не применяются · роутинг управляется сервером';

  @override
  String get homeTrafficLive => 'ТРАФИК — LIVE';

  @override
  String homePeak(String value) {
    return 'пик $value';
  }

  @override
  String commonErrorWith(String error) {
    return 'Ошибка: $error';
  }

  @override
  String get commonRename => 'Переименовать';

  @override
  String get commonDelete => 'Удалить';

  @override
  String get commonName => 'Имя';

  @override
  String get commonCancel => 'Отмена';

  @override
  String get commonSave => 'Сохранить';

  @override
  String get commonContinue => 'Продолжить';

  @override
  String get configsHideGroups => 'скрыть группы';

  @override
  String get configsSortByPing => 'сортировать по ping';

  @override
  String get configsSortMode => 'режим сортировки';

  @override
  String get configsPin => 'Закрепить';

  @override
  String get configsUnpin => 'Открепить';

  @override
  String get configsCore => 'Ядро';

  @override
  String get configsCoreNone => 'нет';

  @override
  String get configsEditUri => 'Редактировать URI';

  @override
  String get configsCopyUrl => 'Копировать URL';

  @override
  String get configsUrlCopied => 'URL скопирован';

  @override
  String get configsShare => 'Поделиться';

  @override
  String get configsUriParseFailed => 'Не удалось распознать URI';

  @override
  String get configsDeleteTitle => 'Удалить?';

  @override
  String configsDeleteMessage(String name) {
    return 'Конфигурация «$name» будет удалена.';
  }

  @override
  String get configsSubUpdated => 'Подписка обновлена';

  @override
  String get certUntrustedTitle => 'Ненадёжный сертификат';

  @override
  String get certUntrustedMessage =>
      'Сервер использует самоподписанный или неизвестный сертификат. Соединение может быть небезопасным.';

  @override
  String certServer(String host) {
    return 'Сервер: $host';
  }

  @override
  String certSubject(String subject) {
    return 'Сертификат: $subject';
  }

  @override
  String certIssuer(String issuer) {
    return 'Издатель: $issuer';
  }

  @override
  String certFingerprint(String fingerprint) {
    return 'SHA-256: $fingerprint';
  }

  @override
  String get certContinueAnyway => 'Продолжить всё равно?';

  @override
  String configsUpdateError(String error) {
    return 'Ошибка обновления: $error';
  }

  @override
  String get configsRenameSub => 'Переименовать подписку';

  @override
  String get configsEditSubUrl => 'Изменить URL подписки';

  @override
  String get configsSaveAndRefresh => 'Сохранить и обновить';

  @override
  String get configsSubUpdatedNewUrl => 'Подписка обновлена по новому URL';

  @override
  String get configsDeleteSubTitle => 'Удалить подписку?';

  @override
  String configsDeleteSubMessage(String name) {
    return 'Подписка «$name» и все её конфигурации будут удалены.';
  }

  @override
  String configsSubsUpdated(int count) {
    return 'Подписки обновлены: $count';
  }

  @override
  String configsSubsUpdatedPartial(int ok, int total) {
    return 'Обновлено $ok из $total';
  }

  @override
  String get configsTagline => 'КОНФИГУРАЦИИ';

  @override
  String get configsDisplaySettings => 'настройки отображения';

  @override
  String get configsSubSettings => 'настройки подписок';

  @override
  String get configsExport => 'экспорт подключений';

  @override
  String get configsRefreshSubs => 'обновить подписки';

  @override
  String get configsAdd => 'добавить';

  @override
  String get subNeverUpdated => 'Не обновлялась';

  @override
  String get subJustNow => 'Только что';

  @override
  String subMinutesAgo(int count) {
    return '$count мин назад';
  }

  @override
  String subHoursAgo(int count) {
    return '$count ч назад';
  }

  @override
  String subDaysAgo(int count) {
    return '$count д назад';
  }

  @override
  String get subExpired => 'Истёк';

  @override
  String get configsSubMenu => 'меню подписки';

  @override
  String configsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count конфига',
      many: '$count конфигов',
      few: '$count конфига',
      one: '$count конфиг',
    );
    return '$_temp0';
  }

  @override
  String get configsAutoSelectReset => 'Сбросить авто-выбор';

  @override
  String get configsAutoSelectBest => 'Авто-выбор лучшего';

  @override
  String get configsEditUrl => 'Изменить URL';

  @override
  String get configsRefresh => 'Обновить';

  @override
  String get configsConfigMenu => 'меню конфигурации';

  @override
  String get configsNotInSub => 'нет в подписке';

  @override
  String get configsPinned => 'закреплённые';

  @override
  String get configsPinUnavailable => 'недоступен · нажмите чтобы открепить';

  @override
  String get configsEmpty => 'Добавьте конфигурацию\nили подписку';

  @override
  String get routingSplitOff => 'выкл · все приложения через VPN';

  @override
  String routingSplitOnly(int count) {
    return '$count прил · ТОЛЬКО';
  }

  @override
  String routingSplitExcept(int count) {
    return '$count прил · КРОМЕ';
  }

  @override
  String get routingModeGlobalHint => 'весь трафик через VPN · правила выключены';

  @override
  String routingModeBypassHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count правила',
      many: '$count правил',
      few: '$count правила',
      one: '$count правило',
    );
    return '$_temp0 · совпавшие напрямую, остальное через VPN';
  }

  @override
  String routingModeOnlyHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count правила',
      many: '$count правил',
      few: '$count правила',
      one: '$count правило',
    );
    return '$_temp0 · только совпавшие через VPN';
  }

  @override
  String get routingGeoMissingHint => 'Загрузите geo-базы (раздел geo.data ниже)';

  @override
  String get routingSniffHint => 'Требует снифинг (переключатель «Снифинг» выше)';

  @override
  String get routingTagline => 'МАРШРУТИЗАЦИЯ · SPLIT-TUNNEL';

  @override
  String get routingSplitTunnel => 'Сплит-туннелирование';

  @override
  String get routingLocalNetworks => 'Локальные сети';

  @override
  String get routingLocalNetworksHint => 'Не туннелировать 10/8, 192.168/16';

  @override
  String get routingAddRegion => 'регион';

  @override
  String get routingSniffing => 'Снифинг';

  @override
  String get routingSniffingHint => 'Определять домен из TLS SNI · нужен для domain.suffix и geosite';

  @override
  String get routingAddSuffix => 'суффикс';

  @override
  String get routingAddCategory => 'категория';

  @override
  String get routingAddSite => 'сайт';

  @override
  String get routingAdBlock => 'Блокировка рекламы';

  @override
  String get routingRuServices => 'Российские сервисы';

  @override
  String get routingRuServicesHint => 'Яндекс, VK, Сбер, Ozon, Авито и др. → выбранный outbound';

  @override
  String get routingKillSwitchHint => 'Блокировать трафик при обрыве VPN';

  @override
  String get routingSource => 'ИСТОЧНИК';

  @override
  String get routingSourceCustom => 'Свой';

  @override
  String get countryRu => 'Россия';

  @override
  String get countryBy => 'Беларусь';

  @override
  String get countryKz => 'Казахстан';

  @override
  String get countryUa => 'Украина';

  @override
  String get countryCn => 'Китай';

  @override
  String get countryUs => 'США';

  @override
  String get countryDe => 'Германия';

  @override
  String get countryGb => 'Великобритания';

  @override
  String get countryFr => 'Франция';

  @override
  String get countryNl => 'Нидерланды';

  @override
  String get countryTr => 'Турция';

  @override
  String get countryJp => 'Япония';

  @override
  String get countrySe => 'Швеция';

  @override
  String get countryFi => 'Финляндия';

  @override
  String get countryPl => 'Польша';

  @override
  String get routingRegions => 'РЕГИОНЫ';

  @override
  String get routingCountries => 'страны';

  @override
  String get routingServices => 'сервисы';

  @override
  String get routingGeoipCustomHint => 'Код или категория (напр. IT, netflix)';

  @override
  String get routingSuffixes => 'СУФФИКСЫ';

  @override
  String get routingDomainCustomHint => 'Домен или зона (напр. example.com)';

  @override
  String get routingSites => 'САЙТЫ';

  @override
  String get routingSiteCustomHint => 'Сайт (напр. example.com)';

  @override
  String get geositeCategoryRu => 'Россия (категория)';

  @override
  String get geositeGeoDetect => 'Geo-detect сервисы';

  @override
  String get geositeGames => 'Игры';

  @override
  String get routingCategories => 'КАТЕГОРИИ';

  @override
  String get routingGeositeCustomHint => 'Категория (напр. geolocation-!cn)';

  @override
  String get routingModeAll => 'весь трафик';

  @override
  String get routingModeRules => 'по правилам';

  @override
  String get routingModeMatch => 'только match';

  @override
  String get commonDone => 'ГОТОВО';

  @override
  String get geoNotLoaded => 'Geo-базы не загружены';

  @override
  String get geoDownload => 'ЗАГРУЗИТЬ';

  @override
  String get geoLoaded => 'Geo-базы загружены';

  @override
  String get geoUpdate => 'ОБНОВИТЬ';

  @override
  String get geoDownloading => 'Загрузка geo-баз...';

  @override
  String get unitMb => 'МБ';

  @override
  String get commonRetryUpper => 'ПОВТОР';

  @override
  String get geoUpdatedToday => 'Обновлено сегодня';

  @override
  String get geoUpdatedYesterday => 'Обновлено вчера';

  @override
  String geoUpdatedDaysAgo(int count) {
    return 'Обновлено $count дн. назад';
  }

  @override
  String get commonApplyUpper => 'ПРИМЕНИТЬ';

  @override
  String get settingsTagline => 'ПАРАМЕТРЫ · ЛОКАЛЬНЫЙ ПРОФИЛЬ';

  @override
  String get settingsProfileLocked => 'профиль заблокирован · только чтение';

  @override
  String settingsProfileAutosave(String name) {
    return 'профиль: $name · автосохранение';
  }

  @override
  String get settingsLogs => 'Логи';

  @override
  String get settingsLogsHint => 'журнал приложения и xray';

  @override
  String get settingsAutoConnect => 'Автоподключение';

  @override
  String get settingsAutoConnectHint => 'Подключаться при запуске приложения';

  @override
  String get settingsStartOnBoot => 'Запуск при загрузке';

  @override
  String get settingsStartOnBootHint => 'Подключаться автоматически при перезагрузке устройства';

  @override
  String get settingsAutomation => 'Автоматизация';

  @override
  String get settingsAutomationHint =>
      'Tasker/Anubis: команды CONNECT/DISCONNECT и рассылка состояния. Любое приложение сможет выключить VPN и узнать, что он включён';

  @override
  String get settingsNotification => 'Уведомление';

  @override
  String get settingsNotificationHint => 'Скорость и кнопка отключения в шторке';

  @override
  String get settingsBattery => 'Оптимизация батареи';

  @override
  String get settingsBatteryHint => 'Чтобы система не останавливала VPN в фоне';

  @override
  String get settingsSubscriptions => 'Подписки';

  @override
  String settingsSubAutoRefreshOn(int hours) {
    return 'автообновление · $hoursч';
  }

  @override
  String get settingsSubAutoRefreshOff => 'автообновление выкл';

  @override
  String get settingsNetwork => 'Сеть';

  @override
  String get settingsProxyOnlyShort => 'только прокси';

  @override
  String get dnsViaVpn => 'через VPN';

  @override
  String get dnsDirect => 'напрямую';

  @override
  String get settingsUpdateChannel => 'Канал обновлений';

  @override
  String get settingsCoreLastEnabled => 'Нужно хотя бы одно включённое ядро';

  @override
  String get settingsCores => 'Ядра';

  @override
  String get settingsCoresHint => 'Профиль запускает первое ядро сверху, которое его поддерживает';

  @override
  String settingsCoreMoveUp(String core) {
    return 'поднять $core';
  }

  @override
  String get settingsCoreUnavailable => 'не загружается на устройстве';

  @override
  String get settingsTheme => 'Тема';

  @override
  String get settingsThemeDark => 'ТЁМНАЯ';

  @override
  String get settingsThemeLight => 'СВЕТЛАЯ';

  @override
  String get settingsSystem => 'СИСТЕМА';

  @override
  String get settingsLanguage => 'Язык';

  @override
  String get settingsFontSize => 'Размер шрифта';

  @override
  String get settingsFontNormal => 'ОБЫЧНЫЙ';

  @override
  String get settingsFontLarge => 'КРУПНЫЙ';

  @override
  String get settingsAccentColor => 'АКЦЕНТНЫЙ ЦВЕТ';

  @override
  String get updateTitle => 'Обновления';

  @override
  String get updateCheck => 'ПРОВЕРИТЬ';

  @override
  String get updateChecking => 'Проверка...';

  @override
  String updateDownloading(String version) {
    return 'Скачивается v$version';
  }

  @override
  String get commonCancelUpper => 'ОТМЕНА';

  @override
  String updateReadyToInstall(String version) {
    return 'v$version готова к установке';
  }

  @override
  String get updateInstall => 'УСТАНОВИТЬ';

  @override
  String get updateAvailable => 'доступно обновление';

  @override
  String get updateUpToDate => 'актуальная версия';

  @override
  String get updateResume => 'ПРОДОЛЖИТЬ';

  @override
  String get updateDownload => 'СКАЧАТЬ';

  @override
  String get updateReinstall => 'ПЕРЕУСТАНОВИТЬ';

  @override
  String get commonLoading => 'загрузка...';

  @override
  String get profileReadonly => 'только чтение';

  @override
  String get settingsProfiles => 'Профили';

  @override
  String get networkTagline => 'СЕТЬ · SOCKS · TUN';

  @override
  String get networkRandomPort => 'Случайный порт';

  @override
  String get networkRandomPortHint => 'Случайный SOCKS порт при каждом подключении';

  @override
  String get networkSocksPort => 'SOCKS5 порт';

  @override
  String get networkRandomCreds => 'Случайные учётные данные';

  @override
  String get networkRandomCredsHint => 'Генерировать случайный логин/пароль SOCKS';

  @override
  String get networkSocksLogin => 'Логин SOCKS';

  @override
  String get networkNoAuth => 'без пароля';

  @override
  String get networkSocksPassword => 'Пароль SOCKS';

  @override
  String get networkProxyOnly => 'Только прокси';

  @override
  String get networkProxyOnlyHint => 'Запустить SOCKS прокси без VPN-туннеля';

  @override
  String get networkUdpHint => 'Разрешить UDP-трафик через SOCKS';

  @override
  String get networkIcmpHint =>
      'Отвечать на ping: прокси ICMP не передаёт, ответ даёт сам VPN — время не отражает задержку до узла';

  @override
  String get networkBlockQuic => 'Блокировать QUIC';

  @override
  String get networkBlockQuicHint =>
      'TUN отвечает на UDP 443 ICMP-ом «порт недоступен»: браузер мгновенно падает на TCP вместо ожидания QUIC-таймаута (~55с). Трафик из устройства не уходит.';

  @override
  String get networkFingerprintHint => 'uTLS-маскировка ClientHello (TLS/REALITY)';

  @override
  String get networkIpv6 => 'IPv6 в туннеле';

  @override
  String get networkIpv6Hint =>
      'Добавить IPv6-адрес на TUN-интерфейс. Включайте только если VPN-сервер имеет IPv6: иначе приложения с IPv6-адресами (Telegram) зависают. При выключении IPv6 блокируется системой без утечек — приложения мгновенно переходят на IPv4.';

  @override
  String get networkObservatoryInterval => 'Observatory мин. интервал, сек';

  @override
  String get networkFragment => 'Фрагментация';

  @override
  String get networkFragmentHint =>
      'Режет исходящий TCP-поток на части, чтобы DPI не собрал ClientHello целиком. Не применяется к Hysteria2 (QUIC поверх UDP).';

  @override
  String get networkFragmentPackets => 'Пакеты';

  @override
  String get networkFragmentLength => 'Длина куска, байт';

  @override
  String get networkPauseMs => 'Пауза, мс';

  @override
  String get networkFragmentInvalid =>
      'Длина и пауза должны быть диапазонами вида 100-200 и 10-20, пакеты — tlshello или диапазон. Фрагментация не применяется.';

  @override
  String get networkNoise => 'Шумы';

  @override
  String get networkNoiseHint =>
      'Мусорные UDP-датаграммы перед первой полезной. Работают только на UDP-плече — Hysteria2 и QUIC-транспорт; на TCP не влияют (там фрагментация). DNS-запросы xray шумом не портит.';

  @override
  String get networkNoiseType => 'Тип пакета';

  @override
  String get networkNoiseTypeHint => 'RAND — случайные байты; STR / HEX / BASE64 — заданный вручную';

  @override
  String get networkNoiseLength => 'Длина, байт';

  @override
  String get networkNoisePacket => 'Пакет';

  @override
  String get networkNoiseContent => 'содержимое';

  @override
  String get networkNoiseInvalidRand => 'Длина должна быть диапазоном вида 50-100, пауза — 10-20. Шумы не применяются.';

  @override
  String get networkNoiseInvalidPacket =>
      'Пакет не должен быть пустым, пауза — диапазон вида 10-20. Шумы не применяются.';

  @override
  String get networkMuxHint =>
      'Мультиплексирует несколько соединений в одно — меньше хендшейков. При XTLS Vision TCP-ветка отключается автоматически (остаётся XUDP). Не применяется к Hysteria2.';

  @override
  String get networkMuxTcp => 'TCP-подпотоки';

  @override
  String get networkMuxXudp => 'XUDP-подпотоки';

  @override
  String get networkMuxQuic => 'QUIC (UDP/443) через mux';

  @override
  String get networkMuxQuicHint => 'reject — отбрасывать, allow — пускать через mux, skip — мимо mux';

  @override
  String get networkProbeType => 'Тип проверки';

  @override
  String get networkProbeTypeHint =>
      'SOCKS — HTTP-запрос через SOCKS5 в xray; XRAYDELAY — замер внутри ядра, сразу даёт задержку; PASSIVE — без активных проб, только метрики tun2socks (экономит батарею, обрыв виден лишь при реальном трафике)';

  @override
  String get networkProbeTarget => 'Адрес проверки';

  @override
  String get networkProbeTargetHint => 'Куда стучится проба. CUSTOM — свой URL ниже';

  @override
  String get networkFailureThreshold => 'Провалов до реакции';

  @override
  String get networkFailAction => 'При потере туннеля';

  @override
  String get networkFailActionHint =>
      'RECONNECT — переподключить тот же сервер; SWITCHCONFIG — уйти на самый быстрый живой конфиг';

  @override
  String get networkSwitchSource => 'Откуда брать конфиг';

  @override
  String get networkSwitchSourceHint =>
      'SUBSCRIPTION — конфиги той же подписки; PINNED — закреплённые; ALL — все сохранённые. Кандидаты проверяются полноценным замером через сам протокол, не TCP-пингом';

  @override
  String get profilesTagline => 'УПРАВЛЕНИЕ · ПРОФИЛИ';

  @override
  String get profilesSubtitle => 'переключение и управление профилями настроек';

  @override
  String get profilesNew => 'Новый профиль';

  @override
  String get profilesNameHint => 'Название профиля';

  @override
  String get profilesCopyCurrent => 'Скопировать текущие настройки';

  @override
  String get commonCreate => 'Создать';

  @override
  String get profileImportTitle => 'Импорт профиля';

  @override
  String get profilesImportHint => 'Вставьте ссылку (teapod://...) или JSON профиля';

  @override
  String get profilesSwitchAfterImport => 'Переключиться после импорта';

  @override
  String get profilesReadonly => 'Только чтение';

  @override
  String get profilesInvalidFormat => 'Неверный формат';

  @override
  String get commonImport => 'Импортировать';

  @override
  String get profilesExportUpper => 'ЭКСПОРТ';

  @override
  String get profilesCopyLink => 'Копировать ссылку';

  @override
  String get profilesLinkCopied => 'Ссылка скопирована';

  @override
  String get profilesShareFile => 'Поделиться файлом';

  @override
  String get profilesDeleteTitle => 'Удалить профиль?';

  @override
  String profilesDeleteMessage(String name) {
    return '«$name» будет удалён без возможности восстановления.';
  }

  @override
  String profilesUpdated(String name) {
    return 'Профиль «$name» обновлён';
  }

  @override
  String get profilesUpdateError => 'Ошибка обновления';

  @override
  String get profilesSwitch => 'Переключиться';

  @override
  String get profilesUnlock => 'Разблокировать';

  @override
  String get profilesLock => 'Заблокировать для редактирования';

  @override
  String get profilesExport => 'Экспортировать';

  @override
  String get deeplinkFetchFailed => 'Не удалось загрузить данные по ссылке';

  @override
  String get splitTethering => 'Раздача через VPN';

  @override
  String get splitTetheringWarning =>
      'Трафик точки доступа неотличим от трафика исключённых приложений. С этой опцией любое исключённое приложение сможет отправить запрос через VPN и узнать IP сервера — например, чтобы сообщить о нём.\n\nВключайте, только если нужна раздача интернета через VPN.';

  @override
  String get commonEnable => 'Включить';

  @override
  String get splitTagline => 'ПРИЛОЖЕНИЯ · SPLIT-TUNNEL';

  @override
  String splitSelectedOnly(int count) {
    return '$count выбрано · только через VPN';
  }

  @override
  String splitExcluded(int count) {
    return '$count исключено · остальное через VPN';
  }

  @override
  String get splitEnabled => 'включено';

  @override
  String get splitDisabled => 'выключено — весь трафик через VPN';

  @override
  String get splitVpnMode => 'Режим VPN';

  @override
  String get splitModeOnly => 'ТОЛЬКО';

  @override
  String get splitModeExcept => 'КРОМЕ';

  @override
  String get splitTetheringHint => 'Пускать в туннель трафик точки доступа';

  @override
  String get splitTetheringWeakened =>
      'Защита ослаблена: исключённые приложения могут выйти через VPN и узнать IP сервера';

  @override
  String get splitSearchHint => 'поиск приложений...';

  @override
  String get splitHideSystem => 'Скрыть системные приложения';

  @override
  String get splitNoApps => 'нет приложений';

  @override
  String get addTagline => 'КОНФИГУРАЦИЯ · НОВЫЙ ПРОФИЛЬ';

  @override
  String addFromClipboard(String text) {
    return 'из буфера: $text';
  }

  @override
  String get addPaste => 'ВСТАВИТЬ';

  @override
  String get addAdd => 'ДОБАВИТЬ';

  @override
  String get addEnterUrl => 'Введите URL';

  @override
  String get addDeeplinkParseFailed => 'Не удалось распознать диплинк';

  @override
  String addImported(String configs, String subscriptions) {
    return 'Импортировано: $configs, $subscriptions';
  }

  @override
  String subscriptionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count подписки',
      many: '$count подписок',
      few: '$count подписки',
      one: '$count подписка',
    );
    return '$_temp0';
  }

  @override
  String get addParseFailed =>
      'Не удалось распознать конфигурацию. Поддерживаются: vless://, vmess://, trojan://, ss://, hy2://, wireguard://, vpn:// (AmneziaVPN) и .conf WireGuard';

  @override
  String get whatsNewTitle => 'Что нового';

  @override
  String get whatsNewTagline => 'ИЗМЕНЕНИЯ · ВСЕ ВЕРСИИ';

  @override
  String get subsTagline => 'ПОДПИСКИ · ОБНОВЛЕНИЕ';

  @override
  String get subsAutoRefresh => 'Автообновление подписок';

  @override
  String get subsAutoRefreshHint => 'Обновлять подписки по расписанию';

  @override
  String get subsInterval => 'Интервал';

  @override
  String unitHours(int count) {
    return '$countч';
  }

  @override
  String get subsHwidHint => 'Отправлять ID устройства для привязки подписки';

  @override
  String get commonDefaultLower => 'по умолчанию';

  @override
  String get logsEmpty => 'Лог пуст';

  @override
  String get logsTagline => 'ЖУРНАЛ · XRAY · TUN2SOCKS';

  @override
  String qrCameraError(String error) {
    return 'Ошибка камеры: $error';
  }

  @override
  String get qrTitle => 'Сканировать QR';

  @override
  String get commonRetry => 'Повторить';

  @override
  String get qrHint => 'Наведите камеру на QR-код';

  @override
  String get commonSaveUpper => 'СОХРАНИТЬ';

  @override
  String get dnsTagline => 'НАСТРОЙКИ · DNS РЕЗОЛВЕР';

  @override
  String get dnsMode => 'Режим DNS';

  @override
  String get dnsViaTunnel => 'через VPN-туннель';

  @override
  String get dnsStrategy => 'DNS стратегия';

  @override
  String get dnsStrategyHint => 'IP-версия для DNS-запросов';

  @override
  String get dnsProtocolType => 'ТИП ПРОТОКОЛА';

  @override
  String get dnsServerAddress => 'АДРЕС СЕРВЕРА';

  @override
  String get coreInUse => 'используется';

  @override
  String get coreCompatible => 'совместимо';

  @override
  String get coreProfileCore => 'ЯДРО ПРОФИЛЯ';

  @override
  String get coreAuto => 'АВТО';

  @override
  String get coreAutoHint =>
      'АВТО — первое подходящее ядро по приоритету из настроек. Закреплённое ядро пробуется первым.';

  @override
  String featureUnsupported(String cores) {
    return 'Не поддерживается: $cores.';
  }

  @override
  String get reconnectBanner => 'настройки изменены · применятся после переподключения';

  @override
  String get reconnectButton => 'ПЕРЕПОДКЛЮЧИТЬ';

  @override
  String get settingsReadonlySnack => 'Профиль только для чтения';

  @override
  String get deeplinkHttpsOnly => 'Импорт по ссылке поддерживает только https';

  @override
  String deeplinkProfile(String name) {
    return 'Профиль: «$name»';
  }

  @override
  String deeplinkExported(String date) {
    return 'Экспорт: $date';
  }

  @override
  String deeplinkSource(String url) {
    return 'Источник: $url';
  }

  @override
  String deeplinkProfileImported(String name) {
    return 'Профиль «$name» импортирован';
  }

  @override
  String get deeplinkConnectionsTitle => 'Импорт подключений';

  @override
  String deeplinkBundle(String label) {
    return 'Набор: «$label»';
  }

  @override
  String deeplinkAdded(String items) {
    return 'Добавлено: $items';
  }

  @override
  String deeplinkAddedNew(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Добавлено: $count новых конфига',
      many: 'Добавлено: $count новых конфигов',
      few: 'Добавлено: $count новых конфига',
      one: 'Добавлено: $count новый конфиг',
    );
    return '$_temp0';
  }

  @override
  String get deeplinkFetchTitle => 'Загрузить по ссылке?';

  @override
  String deeplinkFetchMessage(String host) {
    return 'Данные для импорта будут загружены с $host напрямую, мимо VPN: сервер увидит ваш реальный IP.';
  }

  @override
  String get deeplinkFetchButton => 'Загрузить';

  @override
  String get rustNoRawJson => 'Импорт полного JSON в ядре xray-rust пока недоступен.';

  @override
  String get rustNoFinalmask =>
      'Параметр fm (finalmask) из ссылки ядро xray-rust не применяет. Фрагментацию и шумы задай в настройках сети.';

  @override
  String get rustLinkMux => 'Ссылка требует Mux (mux=on), а в ядре xray-rust его нет.';

  @override
  String get rustVlessEncryption => 'Ядро xray-rust пока принимает VLESS с encryption=none.';

  @override
  String get rustVlessUuid => 'UUID VLESS должен быть настоящим UUID: Rust-ядро не принимает произвольные строки.';

  @override
  String get rustVlessSecurity => 'Для VLESS в ядре xray-rust выбери TLS или Reality.';

  @override
  String get rustVlessFlow => 'Неизвестный VLESS flow.';

  @override
  String get rustVision => 'Vision с encryption=none поддерживается только поверх TCP/RAW с TLS или Reality.';

  @override
  String get rustTrojanPassword => 'Пароль Trojan должен быть непустым и не длиннее 4096 байт.';

  @override
  String get rustTrojanSecurity => 'Trojan в ядре xray-rust работает только с TLS или Reality.';

  @override
  String get rustVmessId => 'id VMess должен быть настоящим UUID: Rust-ядро не принимает произвольные строки.';

  @override
  String rustVmessSecurity(String security) {
    return 'VMess с security=$security из ссылки ядро xray-rust не поддерживает: доступны TLS и транспорт без шифрования.';
  }

  @override
  String rustVmessTls(String value) {
    return 'VMess-ссылка задаёт tls=«$value»: парсер понимает только точное «tls», и профиль ушёл бы без TLS. Исправь значение в ссылке.';
  }

  @override
  String rustSsMethod(String method) {
    return 'Rust-ядро поддерживает только Shadowsocks 2022 (2022-blake3-aes-128-gcm, 2022-blake3-aes-256-gcm, 2022-blake3-chacha20-poly1305). Метод «$method» не поддерживается.';
  }

  @override
  String get rustSsPlugin => 'Плагины Shadowsocks (SIP003, plugin=…) ядро xray-rust не поддерживает.';

  @override
  String get rustSsPrefix => 'Префикс Outline (prefix=…) для Shadowsocks ядро xray-rust не поддерживает.';

  @override
  String get rustTransport => 'Транспорт не поддерживается. Доступны TCP/RAW, WebSocket, HTTPUpgrade, gRPC и xHTTP.';

  @override
  String rustTcpHeader(String header) {
    return 'TCP с HTTP-маскировкой (headerType=$header) Rust-ядро не поддерживает.';
  }

  @override
  String get rustReality => 'Reality поддерживается с TCP/RAW, gRPC и xHTTP. Для WebSocket/HTTPUpgrade нужен TLS.';

  @override
  String get rustEch => 'ECH пока недоступен в ядре xray-rust.';

  @override
  String rustSsOneKey(String method) {
    return 'Для $method нужен один ключ (без identity-ключей через двоеточие).';
  }

  @override
  String rustSsMaxKeys(String method) {
    return 'Для $method допускается до 8 ключей через двоеточие.';
  }

  @override
  String rustSsKey(String method, int bytes) {
    return 'Ключ Shadowsocks 2022 ($method) должен быть base64 с паддингом не короче $bytes байт.';
  }

  @override
  String get rustInsecure =>
      'Rust не поддерживает allowInsecure без pinSHA256. Используй действительный TLS-сертификат или укажи pinSHA256 сертификата сервера.';

  @override
  String rustHy2Obfs(String obfs) {
    return 'Обфускация Hysteria2 «$obfs» не поддерживается: Rust-ядро знает только Salamander.';
  }

  @override
  String get rustSalamanderNoPassword => 'Для Salamander (obfs=salamander) нужен obfs-password.';

  @override
  String get rustSalamanderPassword => 'Пароль Salamander (obfs-password) должен содержать от 4 до 4096 байт.';

  @override
  String get rustPortHopping => 'Список портов для port hopping слишком длинный: Rust-ядро принимает до 65535 портов.';

  @override
  String get rustHy2Password =>
      'Пароль Hysteria2 должен быть непустым, не длиннее 4096 байт и без управляющих символов.';

  @override
  String get rustTunOnly => 'В ядре xray-rust доступен только режим VPN (TUN).';

  @override
  String get rustMux => 'Mux недоступен в ядре xray-rust: выключи его в настройках сети.';

  @override
  String get rustMtu => 'Ядро xray-rust работает с MTU 1500: верни это значение в настройках сети.';

  @override
  String get rustSniffing => 'Включи определение доменов для GeoSite и доменных правил.';

  @override
  String get rustGeositeLimit =>
      'Выбранные категории GeoSite превышают лимит ядра xray-rust в 250 тыс. доменных правил. Убери часть из них или выбери другое ядро.';

  @override
  String get rustFragmentPackets =>
      'Rust-ядро режет только TLS ClientHello: в поле «Пакеты» фрагментации укажи tlshello.';

  @override
  String get rustFragmentLength => 'Длина куска фрагментации в Rust-ядре — от 1 до 16384 байт.';

  @override
  String get rustFragmentDelay => 'Пауза фрагментации в Rust-ядре — не больше 1000 мс.';

  @override
  String get rustFragmentXhttp =>
      'Фрагментацию ClientHello Rust-ядро не применяет к xHTTP с отдельным downloadSettings. Фрагментация — общая настройка: выключи её в настройках сети, чтобы подключиться к этому профилю.';

  @override
  String get rustNoiseSs =>
      'Шумы перед UDP Shadowsocks Rust-ядро не отправляет (только для Hysteria2 и xHTTP поверх HTTP/3). Шумы — общая настройка: выключи их в настройках сети, чтобы подключиться к этому профилю.';

  @override
  String get rustNoiseDelay => 'Пауза шума в Rust-ядре — не больше 1000 мс.';

  @override
  String get rustNoiseHex => 'Шум HEX должен состоять из пар шестнадцатеричных цифр.';

  @override
  String get rustNoiseBase64 => 'Шум BASE64 должен быть стандартным base64 с паддингом.';

  @override
  String get rustNoisePacket => 'Пакет шума в Rust-ядре — не больше 4096 байт.';

  @override
  String coreSingBoxOnly(String protocol) {
    return 'Протокол $protocol поддерживается только ядром sing-box.';
  }

  @override
  String validateNoProtocolParams(String protocol) {
    return 'Нет параметров протокола $protocol';
  }

  @override
  String get validateEmptyAddress => 'Пустой адрес сервера';

  @override
  String validateInvalidPort(int port) {
    return 'Неверный порт: $port';
  }

  @override
  String get validateEmptyUuid => 'Пустой UUID';

  @override
  String get validateEmptyPassword => 'Пустой пароль';

  @override
  String get routingSummaryGlobal => 'Глобальный';

  @override
  String get routingSummaryBypass => 'Обход';

  @override
  String get routingSummaryOnly => 'Только';

  @override
  String get dnsCustomServer => 'Свой сервер';

  @override
  String get coreNoneAvailable => 'Нет доступных ядер.';

  @override
  String get coreUnavailable => 'Не загружается на этом устройстве.';

  @override
  String get coreDisabled => 'Выключено в настройках.';

  @override
  String get wgOneInterface => 'Нужна одна секция [Interface].';

  @override
  String get wgNoPeer => 'Нет секции [Peer].';

  @override
  String wgOnePeer(int count) {
    return 'Поддерживается один [Peer]; в конфиге: $count.';
  }

  @override
  String wgMissingKey(String key) {
    return 'В конфиге нет $key.';
  }

  @override
  String wgInvalidEndpoint(String value) {
    return 'Неверный Endpoint: $value';
  }

  @override
  String get singboxNoNoise => 'Шумы недоступны в ядре sing-box и не применяются.';

  @override
  String get singboxNoMux => 'Mux Xray несовместим с ядром sing-box и не применяется.';

  @override
  String get singboxNoObservatory => 'Observatory и управляемые JSON-конфиги Xray недоступны в ядре sing-box.';

  @override
  String get singboxNoRawConfig => 'Полный JSON-конфиг Xray недоступен в ядре sing-box.';

  @override
  String get singboxNoPqv =>
      'Reality: ядро sing-box не проверяет подпись ML-DSA (pqv) — сервер проверяется только по ключу Reality.';

  @override
  String singboxFragmentMode(String mode) {
    return 'Фрагментация в ядре sing-box — только TLS ClientHello; режим «$mode» не применяется.';
  }

  @override
  String get singboxNoXhttp => 'Транспорт XHTTP недоступен в ядре sing-box.';

  @override
  String get singboxNoXrayExtra => 'Расширенные настройки Xray (finalmask/extra) недоступны в ядре sing-box.';

  @override
  String get singboxLinkMux => 'Ссылка требует Mux Xray (mux=on), а в ядре sing-box его нет.';

  @override
  String get singboxNoCertPin =>
      'Pin сертификата не поддерживается ядром sing-box: оно проверяет только хеш открытого ключа.';

  @override
  String get singboxNoVlessEncryption => 'VLESS Encryption недоступен в ядре sing-box.';

  @override
  String singboxFlow(String flow) {
    return 'Flow «$flow» недоступен в ядре sing-box.';
  }

  @override
  String get singboxNoSsPlugins => 'Плагины Shadowsocks недоступны в ядре sing-box.';

  @override
  String singboxSsMethod(String method) {
    return 'Метод Shadowsocks «$method» недоступен в ядре sing-box.';
  }

  @override
  String get singboxAwgReserved => 'AmneziaWG не поддерживает reserved.';

  @override
  String get singboxAwgHeaders => 'AmneziaWG: защита заголовков требует S1–S4 не меньше 12.';

  @override
  String get singboxNoTcpHttp => 'TCP с HTTP-обфускацией недоступен в ядре sing-box.';

  @override
  String get rustNoProxyOnly => 'Режим «только прокси» недоступен в ядре xray-rust: оно работает только через TUN.';

  @override
  String get rustIcmpLocal => 'ICMP обрабатывается ядром xray-rust локально; настройка не применяется.';

  @override
  String get rustMtuIgnored => 'Ядро xray-rust работает с MTU 1500; другое значение не применяется.';

  @override
  String get rustMuxIgnored => 'Mux недоступен в ядре xray-rust и не применяется.';

  @override
  String get rustNoObservatory => 'Observatory и управляемые JSON-конфиги недоступны в ядре xray-rust.';

  @override
  String get rustNoRawConfig => 'Полный JSON-конфиг недоступен в ядре xray-rust.';

  @override
  String get rustSniffingForced =>
      'Доменные правила в ядре xray-rust требуют определения доменов — оно включено для этого подключения.';

  @override
  String get rustAdBlockDropped =>
      'Блокировка рекламы вместе с выбранными категориями GeoSite превышает лимит ядра xray-rust в 250 тыс. доменных правил — блокировка рекламы не применяется.';

  @override
  String rustGeositeTooLarge(String codes) {
    return 'GeoSite $codes: больше лимита ядра xray-rust на одну категорию (32 МБ или 200 тыс. доменов) — не применяется.';
  }

  @override
  String geositeMissing(String codes) {
    return 'В geosite.dat нет $codes — эти правила не применяются.';
  }

  @override
  String rustFragmentDropped(String reason) {
    return 'Фрагментация не применяется: $reason';
  }

  @override
  String rustNoiseDropped(String reason) {
    return 'Шумы не применяются: $reason';
  }

  @override
  String get xrayNoH2Quic => 'Транспорты HTTP/2 и QUIC удалены из Xray-core: сервер нужно перевести на xHTTP.';

  @override
  String get xrayInsecure =>
      'Xray-core больше не поддерживает allowInsecure: укажи pinSHA256 сертификата сервера или используй действительный сертификат.';

  @override
  String get xrayPinFormat => 'pinSHA256 должен быть SHA-256 сертификата: 64 hex-символа или base64 от 32 байт.';

  @override
  String xrayRawJsonParse(String error) {
    return 'Не удалось разобрать JSON-конфиг подписки: $error';
  }

  @override
  String get profileDefaultName => 'По умолчанию';

  @override
  String get geoNoFilesDir => 'Не удалось получить путь к файлам';

  @override
  String get subHwidLimit => 'Достигнут лимит устройств подписки (HWID)';

  @override
  String get subEmpty => 'Подписка не вернула ни одной конфигурации';

  @override
  String updateUnsupportedDevice(String abi) {
    return 'Устройство не поддерживается: $abi';
  }

  @override
  String get updateNoReleaseInfo => 'Не удалось получить данные о релизе';

  @override
  String updateCheckError(String error) {
    return 'Ошибка проверки: $error';
  }

  @override
  String updateDownloadError(String error) {
    return 'Ошибка загрузки: $error';
  }

  @override
  String get updateInstallError => 'Ошибка установки';

  @override
  String get vpnConnectTimeout => 'Таймаут подключения';

  @override
  String get vpnConnectError => 'Ошибка подключения';

  @override
  String get vpnNoConfigSelected => 'Конфигурация не выбрана';

  @override
  String get importReviewTitle => 'Проверьте перед импортом';

  @override
  String get importReviewTraffic => 'Меняет путь трафика:';

  @override
  String get importReviewSubscriptions => 'Добавляет подписки, приложение будет загружать их с:';

  @override
  String get importChangeKillSwitch => 'Kill switch';

  @override
  String get importChangeDns => 'DNS';

  @override
  String get importChangeRouting => 'Правила маршрутизации';

  @override
  String get importChangeLogLevel => 'Уровень логов';
}
