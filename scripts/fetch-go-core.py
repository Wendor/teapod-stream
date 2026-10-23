#!/usr/bin/env python3
"""Prepare the default Go build without Rust or rustup dependencies."""
import concurrent.futures
from native_downloads import ROOT, GEODATA, GEODATA_VERSION, fetch


def main():
    jobs = [(ROOT / 'android/app/libs/teapod-core.aar',
             'https://github.com/Wendor/teapod-core/releases/download/v1.1.15/teapod-core-1.1.15.aar',
             'df699414098a91da67d1fdffdbccbd93edc344b307d26746ece148e9f8250dc9')]
    jobs += [(ROOT / 'assets/binaries' / name,
              f'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/{GEODATA_VERSION}/{name}', digest)
             for name, digest in GEODATA.items()]
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        for future in [pool.submit(fetch, *job) for job in jobs]:
            future.result()


if __name__ == '__main__':
    main()
