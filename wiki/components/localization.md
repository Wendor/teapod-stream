# Localization

**Files:** `lib/l10n/` (ARB + generated classes, `l10n.dart`), `l10n.yaml`, `lib/providers/locale_provider.dart`,
`android/app/src/main/res/values*/strings.xml`, `AppLocale.kt`

Languages: **English** (template and fallback) and **Russian**. Only what the user sees is localized; comments, logs,
exceptions in native code and tool output are English.

## Flutter (gen_l10n)

- `l10n.yaml`: `arb-dir: lib/l10n`, template `app_en.arb`, class `AppLocalizations`, `nullable-getter: false`.
- `flutter gen-l10n` (also on `pub get` / build) regenerates `app_localizations*.dart`; they are committed, and CI
  fails if they don't match the ARB files.
- Plurals use ICU (`{count, plural, one{…} few{…} many{…} other{…}}`).

| Where | How |
|---|---|
| Widgets | `context.l10n.key` — rebuilds on language change |
| Code without a context (providers, models, builders, parsers) | `L10n.current.key` |

`MaterialApp.builder` sets `L10n.current` on every build. Strings computed earlier and kept in state (a connection
error, `UpdateError`) stay in the old language until recomputed. Text that used to be `static const` is now getters
(core refusal reasons, DNS presets), and exceptions with user-visible text use `L10n.current`.

Key prefixes: `common*`, `home*`, `configs*`, `routing*`, `settings*`, `network*`, `profiles*`, `split*`, `dns*`,
`update*`, `geo*`, `deeplink*`, `cert*`, `rust*` / `singbox*` / `xray*` (core refusals and warnings), `validate*`, `wg*`.

## Language choice

`localeProvider` (`Locale?`, null = system) in SharedPreferences `app_locale` (`en` / `ru`). Not part of profiles or
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
