#!/usr/bin/env python3
"""Build the pinned Rust core with the documented geodata budget patch."""
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / '.native/xray-rust'
COMMIT = '8a86a7f762aba919ff75cad5980a28612ba2dfe8'
TOOLCHAIN = '1.96.0'
NDK_VERSION = '28.2.13676358'
PATCH = ROOT / 'third_party/xray-rust/geo-budgets.patch'
STAMP = ROOT / '.native/rust-build.json'
DEST = ROOT / 'android/xraymobile/src/main/jniLibs'
TARGETS = {'aarch64-linux-android': 'arm64-v8a', 'x86_64-linux-android': 'x86_64'}


def run(args, **kwargs):
    subprocess.run(args, check=True, **kwargs)


def main():
    identity = dict(commit=COMMIT, toolchain=TOOLCHAIN, ndk=NDK_VERSION,
                    patch=hashlib.sha256(PATCH.read_bytes()).hexdigest())
    if STAMP.exists():
        saved = json.loads(STAMP.read_text())
        if saved.get('identity') == identity and all(
                (DEST / abi / 'libxray_ffi.so').is_file() and
                hashlib.sha256((DEST / abi / 'libxray_ffi.so').read_bytes()).hexdigest() == saved.get('sha256', {}).get(abi)
                for abi in TARGETS.values()):
            print('xray-rust 0.6.0+geo.1: verified cached native binaries', flush=True)
            return
    if not shutil.which('rustup'):
        raise RuntimeError('Install rustup to build xray-rust (Rust 1.96.0).')
    sdk = pathlib.Path(os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT') or pathlib.Path.home() / 'Android/Sdk')
    ndk = pathlib.Path(os.environ.get('ANDROID_NDK_HOME') or sdk / 'ndk' / NDK_VERSION)
    host = 'darwin-x86_64' if sys.platform == 'darwin' else 'linux-x86_64'
    compiler = ndk / 'toolchains/llvm/prebuilt' / host / 'bin'
    if not compiler.is_dir():
        raise RuntimeError(f'Android NDK {NDK_VERSION} was not found: {compiler}')
    if not SOURCE.exists():
        SOURCE.parent.mkdir(parents=True, exist_ok=True)
        run(['git', 'init', str(SOURCE)])
        run(['git', '-C', str(SOURCE), 'remote', 'add', 'origin', 'https://github.com/aimalygin/xray-rust.git'])
        run(['git', '-C', str(SOURCE), 'fetch', '--depth=1', 'origin', COMMIT])
        run(['git', '-C', str(SOURCE), 'checkout', '--detach', 'FETCH_HEAD'])
    actual = subprocess.check_output(['git', '-C', str(SOURCE), 'rev-parse', 'HEAD'], text=True).strip()
    if actual != COMMIT:
        raise RuntimeError('Native source revision differs from the pinned commit.')
    applied = subprocess.run(['git', '-C', str(SOURCE), 'apply', '--reverse', '--check', str(PATCH)], capture_output=True).returncode == 0
    if not applied:
        run(['git', '-C', str(SOURCE), 'apply', '--check', str(PATCH)])
        run(['git', '-C', str(SOURCE), 'apply', str(PATCH)])
    run(['rustup', 'toolchain', 'install', TOOLCHAIN, '--profile', 'minimal', '--no-self-update'])
    run(['rustup', 'target', 'add', '--toolchain', TOOLCHAIN, *TARGETS])
    env = os.environ.copy()
    env['CARGO_TARGET_DIR'] = str(ROOT / '.native/target')
    for target in TARGETS:
        key = target.replace('-', '_')
        linker = str(compiler / (target + '24-clang'))
        env[f'CC_{key}'] = linker
        env[f'AR_{key}'] = str(compiler / 'llvm-ar')
        env[f'CARGO_TARGET_{key.upper()}_LINKER'] = linker
        env[f'CARGO_TARGET_{key.upper()}_RUSTFLAGS'] = '-C link-arg=-Wl,-z,max-page-size=16384 -C link-arg=-Wl,-z,common-page-size=16384'
    args = ['rustup', 'run', TOOLCHAIN, 'cargo', 'build', '--release', '--locked', '-p', 'xray-ffi', '-j', '6']
    for target in TARGETS:
        args += ['--target', target]
    run(args, cwd=SOURCE, env=env)
    hashes = {}
    for target, abi in TARGETS.items():
        data = (ROOT / f'.native/target/{target}/release/libxray_ffi.so').read_bytes()
        destination = DEST / abi / 'libxray_ffi.so'
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_suffix('.so.download')
        temporary.write_bytes(data)
        temporary.replace(destination)
        hashes[abi] = hashlib.sha256(data).hexdigest()
    STAMP.write_text(json.dumps(dict(identity=identity, sha256=hashes), indent=2))
    print('xray-rust 0.6.0+geo.1: built both Android architectures', flush=True)


if __name__ == '__main__':
    main()
