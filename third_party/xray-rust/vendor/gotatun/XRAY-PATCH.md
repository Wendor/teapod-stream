# GotaTun provenance and local changes

Upstream: Mullvad GotaTun v0.9.1, commit
`dab390cdf9dcfb7a6fa85dd8798db92b681ad296`.
Archive: `https://codeload.github.com/mullvad/gotatun/tar.gz/dab390cdf9dcfb7a6fa85dd8798db92b681ad296`.
SHA-256: `2a2745851b2989b6d388330b3b9ccfa180ecd12260014b708e01489abae02722`.

The exact source is modified by
`tools/wireguard-adapter-prototype/patches/gotatun-mobile-memory.patch`, then
`tools/wireguard-adapter-prototype/patches/gotatun-psk-hygiene.patch`, then
`tools/wireguard-adapter-prototype/patches/gotatun-mobile-build.patch`, then
`tools/wireguard-adapter-prototype/patches/gotatun-mobile-progress.patch`.
It adds opt-in bounded device resources; see that directory's README for the
changed files and scope. The second patch replaces owned PSK arrays with a
redacted `PresharedKey(Box<Zeroizing<[u8; 32]>>)` through peer, update and Noise
state. Handshake KDF calls borrow it. It adds a direct dependency on the already
locked zeroize 1.8.2 and one edge in the upstream lockfile; no package version is
changed by the PSK patch. Cryptographic algorithms remain upstream's.
The build patch compiles the batched-send size helper only on Linux, Android
and Windows, where it is used. The generic iOS/tvOS implementation does not
call it; the upstream macOS-only exclusion otherwise fails `-D warnings` on
those targets. It also gates privileged kernel-TUN integration tests on the
`tun` feature they require, so the `ring,device` library tests compile on Linux
without kernel-TUN support. The device, memory and protocol tests remain enabled.
No socket or packet behavior changes.
The progress patch releases the peer/device locks after authenticated source
validation and before waiting for inner IP receive capacity. This prevents a
stalled receiver from blocking outgoing encryption for the same peer. Its
bounded-queue regression test also runs in the upstream adapter gate.
`tools/wireguard-adapter-prototype/prepare_vendor.py` copies the crate sources,
README and license notices, expands workspace manifest fields/dependencies and
removes benchmark declarations. It does not copy upstream's privileged TUN runner.

`scripts/check-wireguard-runtime.sh` verifies the archive, applies all four patches with
zero fuzz, regenerates this crate and compares every file except this note. It
then runs engine tests, the IP adapter probe and TCP/UDP/core interoperability
against a freshly built, verified Xray-core v26.7.28 checkout. The
`--verify-vendor-only` option checks source provenance without building or running
the test suites. `GOTATUN_ARCHIVE` supplies an optional checksum-verified local
archive for offline provenance checks.

MPL-2.0 and upstream BSD notices are retained in LICENSE and LICENSE-CLOUDFLARE.
Production selects only `ring,device`; no kernel TUN, UAPI, PCAP or DAITA feature
is enabled. The runtime accepts one peer with optional PSK and rejects nonzero reserved bytes.
