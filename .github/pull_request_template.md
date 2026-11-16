<!-- Rules: CONTRIBUTING.md. Title: `area: what changed`. Replace every <placeholder>; CI checks the sections. -->

## Why

<!-- The problem in plain words: what goes wrong or what is missing, and for whom. Not the implementation.
     Link the issue: "Fixes #N" closes it on merge, "See #N" just links it. -->

<the reason>

## What changed

<!-- Two or three sentences, then the details by area with the files and functions a reviewer should read first. -->

<a short summary>

- <area>: <what changed, files and functions>

## Testing

<!-- Be exact. "Tested on a device" means you ran it: name the device, Android version, core and protocol.
     Native changes (VpnService, cores, TUN, kill switch, reconnect) need a device run or a clear "Not tested". -->

**Tested:** <checks run; on a device: model, Android version, core, protocol, steps>

**Not tested:** <what this could affect that nobody ran, and why — or "Nothing">

## Risks

<!-- What could break for a user after updating: connection, kill switch, reconnect, stored configs/settings
     (migration?), battery. "None" only if you checked. -->

<what could break, or "None">

## Checklist

- [ ] One topic; no unrelated changes.
- [ ] Checks pass: `dart format`, `flutter analyze`, `flutter test`, `./gradlew :app:testDebugUnitTest`.
- [ ] A test for the fix or logic change (or "Not tested" explains why it can't have one).
- [ ] User-visible strings in both `app_en.arb` and `app_ru.arb` (native: `values` and `values-ru`).
- [ ] Wiki pages updated where this change made them wrong.
- [ ] No version bump, release-script, workflow or dependency changes (or agreed in the issue).
- [ ] No secrets: server URIs, subscription links, keys, unmasked logs.
- [ ] AI was used to write this PR, and I have read and understood every line. <!-- delete this box if no AI was used -->
