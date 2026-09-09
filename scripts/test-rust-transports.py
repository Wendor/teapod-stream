#!/usr/bin/env python3
"""Run Android Rust clients against a local, pinned Go Xray server.

Requires a running Android emulator, openssl, Flutter and JDK/Android tools.
Set XRAY_REFERENCE to a local binary, or use the downloaded pinned Linux binary.
No live subscription, user UUID or remote VPN endpoint is used.
"""
import base64
import contextlib
import hashlib
import json
import os
import pathlib
import socket
import socketserver
import ssl
import subprocess
import tempfile
import threading
import time
import urllib.parse
import zipfile
from native_downloads import ROOT, fetch


class Echo(socketserver.BaseRequestHandler):
    def handle(self):
        with contextlib.suppress(OSError):
            self.request.settimeout(20)
            while data := self.request.recv(65536):
                self.request.sendall(data)


class Server(socketserver.ThreadingTCPServer):
    daemon_threads = True
    allow_reuse_address = True


class TlsServer(Server):
    def get_request(self):
        connection, address = super().get_request()
        connection.settimeout(15)
        try:
            return self.tls.wrap_socket(connection, server_side=True), address
        except OSError:
            connection.close()
            raise


def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def main():
    reference = pathlib.Path(os.environ.get('XRAY_REFERENCE', ROOT / '.native/xray-reference/xray'))
    if not reference.exists():
        archive = ROOT / '.native/xray-reference/xray.zip'
        fetch(archive, 'https://github.com/XTLS/Xray-core/releases/download/v26.7.28/Xray-linux-64.zip',
              '8195d909f1109b8f3d99eefe401a3c451d7bf4af71f24d3815420f77e5dd2a40')
        with zipfile.ZipFile(archive) as z:
            reference.write_bytes(z.read('xray'))
        reference.chmod(0o755)
    adb = ['adb'] + (['-s', os.environ['ANDROID_SERIAL']] if os.environ.get('ANDROID_SERIAL') else [])
    fixture_path = '/data/local/tmp/teapod-vless-interop.json'
    with tempfile.TemporaryDirectory(prefix='teapod-vless-interop-') as temp:
        directory = pathlib.Path(temp)
        cert, key = directory / 'certificate.pem', directory / 'key.pem'
        run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
             '-subj', '/CN=cover.example', '-addext', 'subjectAltName=DNS:cover.example',
             '-keyout', str(key), '-out', str(cert)], capture_output=True)
        der = ssl.PEM_cert_to_DER_cert(cert.read_text())
        pin = hashlib.sha256(der).hexdigest()
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls.minimum_version = ssl.TLSVersion.TLSv1_3
        tls.load_cert_chain(cert, key)
        tls.set_alpn_protocols(['h2', 'http/1.1'])
        with Server(('127.0.0.1', 0), Echo) as echo, TlsServer(('127.0.0.1', 0), Echo) as cover:
            cover.tls = tls
            for server in (echo, cover):
                threading.Thread(target=server.serve_forever, daemon=True).start()
            generated = subprocess.check_output([str(reference), 'x25519'], text=True)
            keys = {k.strip().replace(' ', ''): v.strip() for k, v in
                    (line.split(':', 1) for line in generated.splitlines() if ':' in line)}
            public_key = next((value for label, value in keys.items()
                               if 'PublicKey' in label or label.startswith('Password')), None)
            assert public_key and keys.get('PrivateKey'), 'Unexpected Xray x25519 output'
            cases, inbounds = [], []
            combinations = [(t, s, '') for t in ['tcp', 'grpc', 'xhttp'] for s in ['tls', 'reality']]
            combinations += [(t, 'tls', '') for t in ['ws', 'httpupgrade']]
            combinations += [('tcp', s, f) for s in ['reality']
                             for f in ['xtls-rprx-vision', 'xtls-rprx-vision-udp443']]
            if os.environ.get('TEAPOD_INTEROP_VISION_ONLY') == '1':
                combinations = [item for item in combinations if item[2]]
            for transport, security, flow in combinations:
                port = free_port()
                while any(item['port'] == port for item in inbounds):
                    port = free_port()
                name = '-'.join(filter(None, (transport, security, flow)))
                stream = {'network': transport, 'security': security}
                params = dict(type=transport, security=security, encryption='none', fp='firefox',
                              sni='cover.example', host='cover.example', path='/tunnel', mode='auto')
                if flow:
                    params['flow'] = flow
                if security == 'tls':
                    alpn = 'http/1.1' if transport in ['ws', 'httpupgrade'] else 'h2'
                    stream['tlsSettings'] = dict(alpn=[alpn], minVersion='1.3', certificates=[
                        dict(certificateFile=str(cert), keyFile=str(key))])
                    params.update(pinSHA256=pin, alpn=alpn)
                else:
                    stream['realitySettings'] = dict(dest=f'127.0.0.1:{cover.server_address[1]}',
                        serverNames=['cover.example'], privateKey=keys['PrivateKey'], shortIds=['1234abcd'])
                    params.update(pbk=public_key, sid='1234abcd', spx='/')
                if transport in ['ws', 'httpupgrade', 'xhttp']:
                    stream[transport + 'Settings'] = dict(path='/tunnel')
                if transport == 'grpc':
                    stream['grpcSettings'] = dict(serviceName='rpc')
                    params['serviceName'] = 'rpc'
                user = dict(id='11111111-2222-4333-8444-555555555555')
                if flow:
                    user['flow'] = 'xtls-rprx-vision'
                inbounds.append(dict(listen='127.0.0.1', port=port, protocol='vless',
                    settings=dict(clients=[user], decryption='none'), streamSettings=stream))
                url = f'vless://{user["id"]}@10.0.2.2:{port}?' + urllib.parse.urlencode(params)
                cases.append(dict(name=name, url=url))
            source = directory / 'input.json'
            source.write_text(json.dumps(dict(cases=cases, echoPort=echo.server_address[1],
                tlsEchoPort=cover.server_address[1], certificatePem=cert.read_text())))
            config = directory / 'server.json'
            config.write_text(json.dumps(dict(log=dict(loglevel='warning'), inbounds=inbounds,
                outbounds=[dict(protocol='freedom', settings=dict(finalRules=[dict(action='allow')]))])))
            output = directory / 'clients.json'
            env = {k: v for k, v in os.environ.items() if k.lower() not in ['http_proxy', 'https_proxy', 'all_proxy']}
            env.update(TEAPOD_INTEROP_INPUT=str(source), TEAPOD_INTEROP_OUTPUT=str(output), NO_PROXY='localhost,127.0.0.1,::1')
            run(['flutter', 'test', '--dart-define=TEAPOD_CORE=rust', 'test/support/export_vless_interop.dart'], cwd=ROOT, env=env)
            with (directory / 'xray.log').open('w+') as log:
                process = subprocess.Popen([str(reference), 'run', '-config', str(config)], stdout=log, stderr=log)
                try:
                    deadline = time.monotonic() + 15
                    while True:
                        if process.poll() is not None:
                            raise RuntimeError('Local Xray failed to start: ' + config.name)
                        try:
                            with socket.create_connection(('127.0.0.1', inbounds[0]['port']), timeout=1):
                                break
                        except OSError:
                            if time.monotonic() > deadline: raise RuntimeError('Local Xray startup timed out')
                            time.sleep(.1)
                    run(adb + ['push', str(output), fixture_path], capture_output=True)
                    flag = base64.b64encode(b'TEAPOD_CORE=rust').decode()
                    run(['./gradlew', ':xraymobile:connectedDebugAndroidTest', '--console=plain',
                         '-Pdart-defines=' + flag,
                         '-Pandroid.testInstrumentationRunnerArguments.class=org.xrayrust.mobile.VlessTransportInteropTest',
                         '-Pandroid.testInstrumentationRunnerArguments.interopConfig=' + fixture_path],
                        cwd=ROOT / 'android', env=env)
                    print(f'PASS: {len(cases)} VLESS combinations, plain and inner-TLS echo', flush=True)
                except Exception:
                    log.flush(); log.seek(0)
                    print(log.read()[-10000:], flush=True)
                    raise
                finally:
                    process.terminate()
                    try: process.wait(timeout=5)
                    except subprocess.TimeoutExpired: process.kill(); process.wait()
                    subprocess.run(adb + ['shell', 'rm', '-f', fixture_path], capture_output=True)
                    echo.shutdown(); cover.shutdown()


if __name__ == '__main__':
    main()
