#!/usr/bin/env python3
"""Fetch the bundled geodata snapshot, then prepare the patched Rust core."""
import concurrent.futures
import hashlib
import pathlib
import urllib.request
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
GEODATA_VERSION = '202609082347'
GEODATA = {
    'geoip.dat': '4149e607530f91da697bad4696f8c59f0a475af38e69405e4124438c9886c721',
    'geosite.dat': '110be548fd2c2d84249310842667f996e01ab5c753d526717a0f434a5a08e5ea',
}


def fetch(destination, url, sha256):
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() and hashlib.sha256(destination.read_bytes()).hexdigest() == sha256:
        print(f'{destination.name}: verified cached file', flush=True)
        return
    temporary = destination.with_suffix(destination.suffix + '.download')
    try:
        with urllib.request.urlopen(url, timeout=120) as response:
            temporary.write_bytes(response.read())
        if hashlib.sha256(temporary.read_bytes()).hexdigest() != sha256:
            raise RuntimeError(f'{destination.name}: SHA-256 mismatch')
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)
    print(f'{destination.name}: downloaded and verified', flush=True)


def main():
    jobs = []
    for name, digest in GEODATA.items():
        jobs.append((ROOT / 'assets/binaries' / name,
                     f'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/{GEODATA_VERSION}/{name}', digest))
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        for result in [pool.submit(fetch, *job) for job in jobs]:
            result.result()
    subprocess.run([sys.executable, str(ROOT / 'scripts/build-rust-core.py')], check=True)
    print(f'Geodata {GEODATA_VERSION}: ready', flush=True)


if __name__ == '__main__':
    main()
