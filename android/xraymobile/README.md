# Android binding for xray-rust 0.6.1

The Kotlin `XrayCore`, JNI implementation and C header are copied from
https://github.com/aimalygin/xray-rust/tree/ed5258a3a589c2a1f9330142f37c8f3d28a640fa
under MPL-2.0; see ../../third_party/xray-rust/LICENSE.

Local changes add `geodataDirectory` to `XrayCore.create`, calling the existing
`xray_core_set_geodata_search_dir_exclusive` **before** configuration loading.
This avoids global working-directory changes and reflection into private handles.

The native core is built from the same commit with
`third_party/xray-rust/geo-budgets.patch`. It raises three bounded parsing
budgets to accommodate the bundled US GeoIP category (300,531 CIDRs):
500,000 CIDRs per category, 750,000 IP matchers per config, 1,000,000 total
matchers. Our local patch does not change protocol or transport code. The app
reports this build as `xray-rust 0.6.1+geo.1`.

The v0.6.1 Android adapters, JNI implementation and public C ABI are unchanged
from the previous pinned v0.6.0 source; the local geodata-directory extension
is retained.

`scripts/build-rust-core.py` pins Rust 1.96.0 and builds arm64/x86_64 with the
Android NDK 28.2.13676358 and 16 KiB ELF alignment. The source cache and outputs
are ignored under `.native/`; `rust-build.json` records the patch and output
hashes. Distribute the source revision and the patch alongside any binaries.

After a source-pin update, an existing `.native/xray-rust` checkout at the old
revision must be moved aside or explicitly updated before building. The script
rejects a mismatched checkout rather than overwriting local native changes;
with no source checkout, it fetches the exact pinned commit automatically.
