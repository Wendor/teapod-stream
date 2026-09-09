# Third-Party Notices

This project can download and bundle the routing-data files listed below.
Those files are not covered by the project's own source-code license. If you
redistribute an application containing them, retain these notices and comply
with their respective licenses.

The pinned versions and checksums below are also enforced by
`scripts/fetch-geodata.sh`.

## uTLS-derived ClientHello profile data

- Project:
  [refraction-networking/uTLS](https://github.com/refraction-networking/utls)
- Pinned Go module:
  `v1.8.3-0.20260301010127-aa6edf4b11af`
- Upstream revision:
  [`aa6edf4b11af`](https://github.com/refraction-networking/utls/tree/aa6edf4b11af)
- License: BSD 3-Clause
- Upstream license:
  [uTLS LICENSE](https://github.com/refraction-networking/utls/blob/aa6edf4b11af/LICENSE)

The profile-name set in `crates/xray-utls` mirrors Xray/uTLS identifiers. The
deterministic tools under `tools/reality-oracle/` execute the pinned uTLS
implementation, and their reviewed output supplies ClientHello ordering,
protocol identifiers, and lengths used by
`crates/xray-transport/src/utls_profiles.rs`.

Copyright (c) 2009 The Go Authors. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

- Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.
- Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.
- Neither the name of Google Inc. nor the names of its contributors may be
  used to endorse or promote products derived from this software without
  specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

## Gradle Wrapper

- Project: [Gradle](https://github.com/gradle/gradle)
- Wrapper version: `8.14.2`
- License:
  [Apache License 2.0](https://github.com/gradle/gradle/blob/v8.14.2/LICENSE)

The repository includes Gradle's wrapper scripts and
`platform/android/gradle/wrapper/gradle-wrapper.jar`. The scripts retain their
upstream notice, the JAR contains the complete license at `META-INF/LICENSE`,
and CI verifies the JAR and distribution checksums.

## V2Fly GeoIP

- Project: [v2fly/geoip](https://github.com/v2fly/geoip)
- Pinned release:
  [`202607171233`](https://github.com/v2fly/geoip/releases/tag/202607171233)
- Downloaded file: `geoip.dat`
- SHA-256:
  `b71d1999439dde2de2d2b6844a2befa50c50211ff739785c005ca7c230a17d6a`
- Project license:
  [Creative Commons Attribution-ShareAlike 4.0 International](https://creativecommons.org/licenses/by-sa/4.0/)
- Upstream license text:
  [v2fly/geoip LICENSE](https://github.com/v2fly/geoip/blob/202607171233/LICENSE)

The pinned upstream build configuration creates `geoip.dat` from DB-IP
Country Lite data plus private and test network ranges. The DB-IP data is
provided by [DB-IP](https://db-ip.com) under the
[Creative Commons Attribution 4.0 International license](https://creativecommons.org/licenses/by/4.0/).

Attribution: GeoIP routing data by the V2Fly GeoIP project. IP geolocation
data by DB-IP.

No local modifications are made to the downloaded `geoip.dat` file.

## V2Fly Domain List Community

- Project:
  [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)
- Pinned release:
  [`20260727084448`](https://github.com/v2fly/domain-list-community/releases/tag/20260727084448)
- Upstream file: `dlc.dat`
- Installed name: `geosite.dat`
- SHA-256:
  `d6787cf3d08b86402640e8c2a7a18c8d64b31944ffa5274d8a6e154c8f3ddc07`
- License: MIT
- Upstream license text:
  [v2fly/domain-list-community LICENSE](https://github.com/v2fly/domain-list-community/blob/20260727084448/LICENSE)

The downloaded bytes are not modified; only the filename is changed from
`dlc.dat` to the conventional runtime name `geosite.dat`.

Copyright (c) 2018-2019 V2Ray

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
