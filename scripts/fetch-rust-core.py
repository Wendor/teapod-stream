#!/usr/bin/env python3
"""Prepare the experimental Rust core and the shared bundled geodata."""
import concurrent.futures
import subprocess
import sys
from native_downloads import ROOT, GEODATA, GEODATA_VERSION, fetch


def main():
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(fetch, ROOT / 'assets/binaries' / name,
            f'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/{GEODATA_VERSION}/{name}', digest)
            for name, digest in GEODATA.items()]
        for future in futures:
            future.result()
    subprocess.run([sys.executable, str(ROOT / 'scripts/build-rust-core.py')], check=True)


if __name__ == '__main__':
    main()
