# Localization

**Files:** `lib/l10n/` (ARB + generated classes, `l10n.dart`), `l10n.yaml`, `lib/providers/locale_provider.dart`,
`android/app/src/main/res/values*/strings.xml`, `AppLocale.kt`

Languages: **English** (template and fallback) and **Russian**. Only what the user sees is localized; comments, logs,
exceptions in native code and tool output are English.

Exception: the terminal-style captions of the console look stay English in both languages by design — status
tags (`ONLINE`, `OFFLINE`, `HANDSHAKE`, `LOCKED`), section and key labels (`CONFIG`, `version`, `changelog`,
`licenses`, `source`), bracketed tags (`[core]`). They are part of the visual style, like a monospace font. In the
Flutter UI, sentences, buttons, hints, errors, dialogs and values the user has to read go through ARB; native text
(notification, tile) through `values*/strings.xml`; text from outside the app (a server, a core) rides as
`AppMessage.text`.

## Flutter (gen_l10n)

- `l10n.yaml`: `arb-dir: lib/l10n`, template `app_en.arb`, class `AppLocalizations`, `nullable-getter: false`.
- `flutter gen-l10n` (also on `pub get` / build) regenerates `app_localizations*.dart`; they are committed, and CI
  fails if they don't match the ARB files.
- Plurals use ICU (`{count, plural, one{…} few{…} many{…} other{…}}`).

| Where | How |
|---|---|
| Widgets | `context.l10n.key` — rebuilds on language change |
| State in providers (errors, refusals) | `AppMessage` (`lib/core/models/app_message.dart`), localized by the widget (`message.localize(context.l10n)`): a `MessageCode` with its argument where code tells messages apart (the resolver's `coreDisabled` / `coreUnavailable` / `coreNoneAvailable`); `AppMessage.l10n((l) => l.key(args))` for an app string nobody compares (a backend's refusal or warning); `AppMessage.text` for text from outside the app's strings (native, a server, an exception) |
| Reasons in models, builders, parsers | Returned as `AppMessage` (`CoreBackend.checkConfig` / `unavailableReason` / `checkOptions`, the builders' `unsupportedReason`, `VpnConfig.validate`, `VpnProtocol.singBoxOnlyReason`); thrown as `ReasonException(AppMessage)` — a `FormatException` whose `message` is the text of the moment (a builder refusing at build time, `VlessParser.parseUri`, `WireGuardParser.parseConf`). `ReasonException.of(e)` takes the reason of any `FormatException` |
| Logs, `toString()` | `L10n.current` (through `AppMessage.toString`) |

Models, builders, parsers and providers don't read `L10n.current`: a code or an `AppMessage.l10n` in state follows a
language change — the resolver caches a `CoreResolution` per config, and its reasons are localized when shown; a
connect the builder refuses (`ReasonException`, passed through `XrayEngine.connect`) fails with the reason itself.
`MaterialApp.builder` sets `L10n.current` on every build, for logs and `toString()`. The custom DNS server's label is
added by the DNS screen. `AppMessage` is also an `Exception` (a subscription that returned nothing):
`'$e'` in a catch and log lines go through `toString()`, which uses `L10n.current`. The first profile's name
(`Profile.initial`, the one model that reads `L10n.current`) is localized once at startup and is user data from then
on.

Key prefixes: `common*`, `home*`, `configs*`, `routing*`, `settings*`, `network*`, `profiles*`, `split*`, `dns*`,
`update*`, `geo*`, `deeplink*`, `cert*`, `rust*` / `singbox*` / `xray*` (core refusals and warnings), `validate*`, `wg*`.

## Language choice

`localeProvider` (`Locale?`, null = system) in SharedPreferences `app_locale` (`en` / `ru`) through `UiPrefsService`. Not part of profiles or
the connection fingerprint. UI: Settings → appearance → language.

## Android

Notification, channel and tile texts are resources in `values/strings.xml` (en) and `values-ru/strings.xml`.
`Context.appString(id)` reads `flutter.app_locale` from Flutter's SharedPreferences on each call and resolves the
string with that locale (system when unset), so the choice applies on the next notification or tile update.

## Tests

`test/l10n/arb_test.dart` — every key has a translation and placeholders match. UI tests pump with
`AppLocalizations.localizationsDelegates` and locale `en`; expectations are English.

## Adding a language

1. `lib/l10n/app_<code>.arb` with all keys.
2. `android/app/src/main/res/values-<code>/strings.xml`.
3. A segment in the language picker (`settings_screen.dart`).
4. `changelog/<code>.md` with every version and the language in `releaseNotesLanguages`
   ([release notes](ci.md#release-notes)).
