#!/usr/bin/env python3
"""Run Android Rust clients against a local, pinned Go Xray server.

Requires a running Android emulator, openssl, Flutter and JDK/Android tools.
Set XRAY_REFERENCE to a local binary, or use the downloaded pinned Linux binary.
No live subscription, user UUID or remote VPN endpoint is used; every key,
password and certificate is generated for the run.

Client configs come from the production share-link parser and Rust builder
(test/support/export_vless_interop.dart). Every case sends plain and inner-TLS
payloads through the local SOCKS inbound and runs the in-core outbound probe
(XRAYDELAY) through its proxy leaf and the switchConfig candidate probe in a
temporary core, against a local HTTP 204 endpoint. Groups (case names in
brackets):

  vless     8 VLESS carrier/security combinations [tcp-tls, grpc-reality, ...]
  vision    Vision and Vision-udp443 over TCP with TLS and REALITY [tcp-tls-xtls-rprx-vision, ...]
  trojan    Trojan TCP/TLS (+ SOCKS UDP), WebSocket/TLS, TCP/REALITY [trojan-tcp-tls, ...]
  vmess     VMess AEAD TCP/TLS chacha20-poly1305 (+ SOCKS UDP), WebSocket/TLS auto [vmess-tcp-tls, vmess-ws-tls]
  ss        Shadowsocks 2022, each method plus an AES identity-key chain, TCP and SOCKS UDP [ss-2022-blake3-aes-128-gcm, ...]
  hysteria  Hysteria2 with a pin, insecure=1 + pin, Salamander, UDP noise, both [hysteria2-pin, ...]
  fragment  TLS ClientHello fragmentation over TCP/TLS, TCP/REALITY, REALITY + Vision [tcp-tls-fragment, ...]
  udp       Hysteria2 with UDP on, QUIC blocked, UDP off: SOCKS UDP and TUN packets
            to the UDP echo and to port 443, which the server redirects to the
            same echo [hysteria2-udp-control, hysteria2-quic-block, hysteria2-udp-off]

Environment:
  TEAPOD_INTEROP_GROUPS=trojan,ss   only these groups (default: all)
  TEAPOD_INTEROP_CASES=name,...     only these cases (after the group filter)
  TEAPOD_INTEROP_VISION_ONLY=1      same as TEAPOD_INTEROP_GROUPS=vision
  TEAPOD_INTEROP_HYSTERIA_ONLY=1    same as TEAPOD_INTEROP_GROUPS=hysteria
  TEAPOD_INTEROP_CHECK_ONLY=1       no device: check the server config with
                                    `xray run -test` and every exported client
                                    and probe config with `xray-rust config check`
  XRAY_RUST_CLI=path                xray-rust host CLI for the config check
                                    (default .native/host-cli-0.8.1/xray-rust;
                                    a device run skips the check without it)
  TEAPOD_INTEROP_WORKDIR=dir        keep the certificate, server and client
                                    configs and xray.log there instead of a
                                    temporary directory
  ANDROID_SERIAL                    the adb device to use
"""
import base64
import contextlib
import hashlib
import http.server
import json
import os
import pathlib
import secrets
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

UUID = '11111111-2222-4333-8444-555555555555'
GROUPS = ('vless', 'vision', 'trojan', 'vmess', 'ss', 'hysteria', 'fragment', 'udp')
SS2022 = {'2022-blake3-aes-128-gcm': 16, '2022-blake3-aes-256-gcm': 32, '2022-blake3-chacha20-poly1305': 32}
# The app's defaults; the builder writes them as finalmask fragment / noise.
FRAGMENT = dict(packets='tlshello', length='100-200', interval='10-20')
NOISE = dict(type='rand', packet='50-100', delay='10-20')


class Echo(socketserver.BaseRequestHandler):
    def handle(self):
        with contextlib.suppress(OSError):
            self.request.settimeout(20)
            while data := self.request.recv(65536):
                self.request.sendall(data)


class UdpEcho(socketserver.BaseRequestHandler):
    def handle(self):
        data, sock = self.request
        with contextlib.suppress(OSError):
            sock.sendto(data, self.client_address)


class NoContent(http.server.BaseHTTPRequestHandler):
    """generate_204 for the outbound probes; the Rust probe reads only the status line."""
    def do_GET(self):
        self.send_response(204)
        self.send_header('Content-Length', '0')
        self.end_headers()

    def log_message(self, *args):
        pass


class Server(socketserver.ThreadingTCPServer):
    daemon_threads = True
    allow_reuse_address = True


class UdpServer(socketserver.ThreadingUDPServer):
    daemon_threads = True


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


def reference_binary():
    reference = pathlib.Path(os.environ.get('XRAY_REFERENCE', ROOT / '.native/xray-reference/xray'))
    if not reference.exists():
        archive = ROOT / '.native/xray-reference/xray.zip'
        fetch(archive, 'https://github.com/XTLS/Xray-core/releases/download/v26.7.28/Xray-linux-64.zip',
              '8195d909f1109b8f3d99eefe401a3c451d7bf4af71f24d3815420f77e5dd2a40')
        with zipfile.ZipFile(archive) as z:
            reference.write_bytes(z.read('xray'))
        reference.chmod(0o755)
    return reference


def selection():
    """Groups and case names chosen through the environment."""
    groups = [g.strip() for g in os.environ.get('TEAPOD_INTEROP_GROUPS', '').split(',') if g.strip()]
    if os.environ.get('TEAPOD_INTEROP_VISION_ONLY') == '1':
        groups.append('vision')
    if os.environ.get('TEAPOD_INTEROP_HYSTERIA_ONLY') == '1':
        groups.append('hysteria')
    unknown = set(groups) - set(GROUPS)
    if unknown:
        raise SystemExit(f'Unknown TEAPOD_INTEROP_GROUPS {sorted(unknown)}; known: {", ".join(GROUPS)}')
    names = {n.strip() for n in os.environ.get('TEAPOD_INTEROP_CASES', '').split(',') if n.strip()}
    return set(groups or GROUPS), names


class Plan:
    """Cases for the device and the matching inbounds of the reference server."""

    def __init__(self, reference, cert, key, pin, cover_port, udp_echo_port):
        self.cert, self.key, self.pin = str(cert), str(key), pin
        self.cover_port = cover_port
        self.cases, self.inbounds, self.shared = [], [], {}
        generated = subprocess.check_output([str(reference), 'x25519'], text=True)
        keys = {k.strip().replace(' ', ''): v.strip() for k, v in
                (line.split(':', 1) for line in generated.splitlines() if ':' in line)}
        self.public_key = next((value for label, value in keys.items()
                                if 'PublicKey' in label or label.startswith('Password')), None)
        self.private_key = keys.get('PrivateKey')
        assert self.public_key and self.private_key, 'Unexpected Xray x25519 output'
        # UDP/443 of every inbound goes to the UDP echo, so the TUN check can
        # tell the client's QUIC block from a closed port on the host.
        self.server_extra = dict(
            outbounds=[dict(tag='udp443-echo', protocol='freedom', settings=dict(
                redirect=f'127.0.0.1:{udp_echo_port}', finalRules=[dict(action='allow')]))],
            rules=[dict(type='field', network='udp', port='443', outboundTag='udp443-echo')])

    def port(self, kind=socket.SOCK_STREAM):
        while True:
            with socket.socket(socket.AF_INET, kind) as sock:
                sock.bind(('127.0.0.1', 0))
                port = sock.getsockname()[1]
            if all(item['port'] != port for item in self.inbounds):
                return port

    def inbound(self, protocol, settings, stream=None, kind=socket.SOCK_STREAM):
        port = self.port(kind)
        self.inbounds.append(dict(listen='127.0.0.1', port=port, protocol=protocol, settings=settings,
                                  **({'streamSettings': stream} if stream else {})))
        return port

    def add(self, name, url, **expect):
        self.cases.append(dict(name=name, url=url, **expect))

    def stream(self, transport, security, alpn):
        """Server stream settings and the matching share-link parameters."""
        stream = {'network': transport, 'security': security}
        params = dict(type=transport, security=security, fp='firefox', sni='cover.example',
                      host='cover.example', path='/tunnel', mode='auto')
        if security == 'tls':
            stream['tlsSettings'] = dict(alpn=[alpn], minVersion='1.3', certificates=[
                dict(certificateFile=self.cert, keyFile=self.key)])
            params.update(pinSHA256=self.pin, alpn=alpn)
        else:
            stream['realitySettings'] = dict(dest=f'127.0.0.1:{self.cover_port}', serverNames=['cover.example'],
                                             privateKey=self.private_key, shortIds=['1234abcd'])
            params.update(pbk=self.public_key, sid='1234abcd', spx='/')
        if transport in ['ws', 'httpupgrade', 'xhttp']:
            stream[transport + 'Settings'] = dict(path='/tunnel')
        if transport == 'grpc':
            stream['grpcSettings'] = dict(serviceName='rpc')
            params['serviceName'] = 'rpc'
        return stream, params

    def vless(self, name, transport, security, flow='', **expect):
        alpn = 'http/1.1' if transport in ['ws', 'httpupgrade'] else 'h2'
        stream, params = self.stream(transport, security, alpn)
        params['encryption'] = 'none'
        if flow:
            params['flow'] = flow
        user = dict(id=UUID, **({'flow': 'xtls-rprx-vision'} if flow else {}))
        port = self.inbound('vless', dict(clients=[user], decryption='none'), stream)
        self.add(name, f'vless://{UUID}@10.0.2.2:{port}?' + urllib.parse.urlencode(params), **expect)

    def trojan(self, transport, security, **expect):
        alpn = 'http/1.1' if transport == 'ws' else 'h2'
        stream, params = self.stream(transport, security, alpn)
        password = secrets.token_hex(16)
        port = self.inbound('trojan', dict(clients=[dict(password=password)]), stream)
        self.add(f'trojan-{transport}-{security}',
                 f'trojan://{password}@10.0.2.2:{port}?' + urllib.parse.urlencode(params), **expect)

    def vmess(self, transport, cipher, **expect):
        # Standard v2 JSON link. It has no certificate pin field, so the exporter
        # pins the test certificate on the parsed profile (`pin`).
        alpn = 'http/1.1' if transport == 'ws' else 'h2'
        stream, _ = self.stream(transport, 'tls', alpn)
        port = self.inbound('vmess', dict(clients=[dict(id=UUID)]), stream)
        body = dict(v='2', ps=f'vmess-{transport}', add='10.0.2.2', port=str(port), id=UUID, aid='0',
                    scy=cipher, net=transport, type='none', host='cover.example', path='/tunnel',
                    tls='tls', sni='cover.example')
        self.add(f'vmess-{transport}-tls',
                 'vmess://' + base64.b64encode(json.dumps(body).encode()).decode(), pin=self.pin, **expect)

    def shadowsocks(self, method, identity=False, **expect):
        key = lambda: base64.b64encode(secrets.token_bytes(SS2022[method])).decode()
        server = key()
        settings = dict(method=method, password=server, network='tcp,udp')
        password = server
        if identity:
            # Multi-user server: the client sends identity key, then its own key.
            user = key()
            settings['clients'] = [dict(password=user)]
            password = f'{server}:{user}'
        port = self.inbound('shadowsocks', settings)
        if identity:
            # SIP002 base64url userinfo, the other spelling the parser reads.
            userinfo = base64.urlsafe_b64encode(f'{method}:{password}'.encode()).decode().rstrip('=')
        else:
            userinfo = f'{method}:{urllib.parse.quote(password, safe="")}'
        self.add(f'ss-{method}' + ('-identity' if identity else ''),
                 f'ss://{userinfo}@10.0.2.2:{port}#ss', **expect)

    def hysteria(self, name, salamander=False, query=(), **expect):
        """One shared UDP inbound per obfuscation; the certificate is self-signed,
        so Rust trusts it only through pinSHA256."""
        kind = 'salamander' if salamander else 'plain'
        if kind not in self.shared:
            auth = secrets.token_hex(16)
            obfs = secrets.token_hex(12) if salamander else None
            stream = dict(network='hysteria', security='tls', hysteriaSettings=dict(version=2),
                          tlsSettings=dict(alpn=['h3'], certificates=[
                              dict(certificateFile=self.cert, keyFile=self.key)]))
            if obfs:
                stream['finalmask'] = dict(udp=[dict(type='salamander', settings=dict(password=obfs))])
            port = self.inbound('hysteria', dict(version=2, users=[dict(auth=auth)]), stream, socket.SOCK_DGRAM)
            self.shared[kind] = (auth, port, obfs)
        auth, port, obfs = self.shared[kind]
        params = dict(query, sni='cover.example', pinSHA256=self.pin)
        if obfs:
            params.update({'obfs': 'salamander', 'obfs-password': obfs})
        # Official share-link form: `host:port/?query`.
        self.add(name, f'hysteria2://{auth}@10.0.2.2:{port}/?' + urllib.parse.urlencode(params), **expect)


def plan_cases(plan, groups, names):
    wanted = lambda group, name: group in groups and (not names or name in names)
    for transport in ['tcp', 'grpc', 'xhttp']:
        for security in ['tls', 'reality']:
            if wanted('vless', f'{transport}-{security}'):
                plan.vless(f'{transport}-{security}', transport, security)
    for transport in ['ws', 'httpupgrade']:
        if wanted('vless', f'{transport}-tls'):
            plan.vless(f'{transport}-tls', transport, 'tls')
    # xray-rust 0.8.0 fixed Vision direct mode beneath plain TLS.
    for security in ['tls', 'reality']:
        for flow in ['xtls-rprx-vision', 'xtls-rprx-vision-udp443']:
            if wanted('vision', f'tcp-{security}-{flow}'):
                plan.vless(f'tcp-{security}-{flow}', 'tcp', security, flow)
    for transport, security, expect in [('tcp', 'tls', dict(udpEcho=True)), ('ws', 'tls', {}), ('tcp', 'reality', {})]:
        if wanted('trojan', f'trojan-{transport}-{security}'):
            plan.trojan(transport, security, **expect)
    for transport, cipher, expect in [('tcp', 'chacha20-poly1305', dict(udpEcho=True)), ('ws', 'auto', {})]:
        if wanted('vmess', f'vmess-{transport}-tls'):
            plan.vmess(transport, cipher, **expect)
    for method in SS2022:
        if wanted('ss', f'ss-{method}'):
            plan.shadowsocks(method, udpEcho=True)
    if wanted('ss', 'ss-2022-blake3-aes-128-gcm-identity'):
        plan.shadowsocks('2022-blake3-aes-128-gcm', identity=True, udpEcho=True)
    noise = dict(noise=NOISE)
    for name, salamander, query, options in [
        ('hysteria2-pin', False, {}, {}),
        # A pin wins over insecure=1.
        ('hysteria2-insecure-pin', False, {'insecure': '1'}, {}),
        ('hysteria2-salamander', True, {}, {}),
        ('hysteria2-noise', False, {}, noise),
        ('hysteria2-salamander-noise', True, {}, noise),
    ]:
        if wanted('hysteria', name):
            plan.hysteria(name, salamander, query, udpEcho=True, **({'options': options} if options else {}))
    for name, security, flow in [('tcp-tls-fragment', 'tls', ''), ('tcp-reality-fragment', 'reality', ''),
                                 ('tcp-reality-xtls-rprx-vision-fragment', 'reality', 'xtls-rprx-vision')]:
        if wanted('fragment', name):
            plan.vless(name, 'tcp', security, flow, options=dict(fragment=FRAGMENT))
    # The QUIC block and the UDP switch act on TUN flows (a routing rule to the
    # blackhole); with UDP off the local SOCKS drops UDP too. The Hysteria2
    # carrier itself is QUIC and keeps working.
    for name, options, expect in [
        ('hysteria2-udp-control', {}, dict(udpEcho=True, tunUdp=dict(echo=True, quic=True))),
        ('hysteria2-quic-block', dict(blockQuic=True), dict(udpEcho=True, tunUdp=dict(echo=True, quic=False))),
        ('hysteria2-udp-off', dict(enableUdp=False), dict(udpBlocked=True, tunUdp=dict(echo=False, quic=False))),
    ]:
        if wanted('udp', name):
            plan.hysteria(name, options=options, **expect)
    missing = names - {case['name'] for case in plan.cases}
    if missing:
        raise SystemExit(f'TEAPOD_INTEROP_CASES not in the selected groups: {sorted(missing)}')
    if not plan.cases:
        raise SystemExit('No interop cases selected')


def server_config(plan):
    return dict(log=dict(loglevel='warning'), inbounds=plan.inbounds,
                outbounds=[dict(protocol='freedom', settings=dict(finalRules=[dict(action='allow')])),
                           *plan.server_extra['outbounds']],
                routing=dict(rules=plan.server_extra['rules']))


def export_clients(source, output):
    env = {k: v for k, v in os.environ.items() if k.lower() not in ['http_proxy', 'https_proxy', 'all_proxy']}
    env.update(TEAPOD_INTEROP_INPUT=str(source), TEAPOD_INTEROP_OUTPUT=str(output), NO_PROXY='localhost,127.0.0.1,::1')
    run(['flutter', 'test', '--dart-define=TEAPOD_CORE=rust', 'test/support/export_vless_interop.dart'], cwd=ROOT, env=env)
    return env


def check_configs(reference, cli, directory, config, output):
    """`xray run -test` for the server, `xray-rust config check` for each client."""
    result = subprocess.run([str(reference), 'run', '-test', '-config', str(config)], capture_output=True, text=True)
    if result.returncode != 0 or 'Configuration OK' not in result.stdout:
        raise RuntimeError('Reference server config rejected:\n' + result.stdout[-4000:] + result.stderr[-4000:])
    print('server config: Configuration OK', flush=True)
    failures = []
    for case in json.loads(output.read_text())['cases']:
        for kind in ['config', 'probe']:
            path = directory / f'{kind}-{case["name"]}.json'
            path.write_text(case[kind])
            check = subprocess.run([str(cli), 'config', 'check', '-config', str(path), '--json',
                                    '--geodata-dir', str(ROOT / 'assets/binaries')], capture_output=True, text=True)
            try:
                report = json.loads(check.stdout)
            except ValueError:
                report = {'valid': False, 'diagnostics': [check.stdout[-2000:] + check.stderr[-2000:]]}
            if check.returncode != 0 or not report.get('valid') or report.get('diagnostics'):
                failures.append(f'{case["name"]} {kind}: {json.dumps(report.get("diagnostics"))[:600]}')
    if failures:
        raise RuntimeError('xray-rust config check:\n' + '\n'.join(failures))
    print(f'client configs: {len(json.loads(output.read_text())["cases"])} cases, '
          'VPN and probe configs valid with no diagnostics', flush=True)


@contextlib.contextmanager
def local_servers(cert, key):
    """TCP echo, TLS echo (the REALITY cover), UDP echo and HTTP 204 on host loopback."""
    tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    tls.minimum_version = ssl.TLSVersion.TLSv1_3
    tls.load_cert_chain(cert, key)
    tls.set_alpn_protocols(['h2', 'http/1.1'])
    with Server(('127.0.0.1', 0), Echo) as echo, TlsServer(('127.0.0.1', 0), Echo) as cover, \
            UdpServer(('127.0.0.1', 0), UdpEcho) as udp_echo, \
            http.server.ThreadingHTTPServer(('127.0.0.1', 0), NoContent) as no_content:
        cover.tls = tls
        servers = (echo, cover, udp_echo, no_content)
        for server in servers:
            threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            yield dict(echoPort=echo.server_address[1], tlsEchoPort=cover.server_address[1],
                       udpEchoPort=udp_echo.server_address[1], probePort=no_content.server_address[1])
        finally:
            for server in servers:
                server.shutdown()


def certificate(directory):
    cert, key = directory / 'certificate.pem', directory / 'key.pem'
    run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
         '-subj', '/CN=cover.example', '-addext', 'subjectAltName=DNS:cover.example',
         '-keyout', str(key), '-out', str(cert)], capture_output=True)
    return cert, key, hashlib.sha256(ssl.PEM_cert_to_DER_cert(cert.read_text())).hexdigest()


@contextlib.contextmanager
def reference_server(reference, config, log_path, inbounds):
    with log_path.open('w+') as log:
        process = subprocess.Popen([str(reference), 'run', '-config', str(config)], stdout=log, stderr=log)
        try:
            # A UDP inbound cannot be probed with a TCP connect. Xray logs
            # "Xray <version> started" (warning level) after every inbound
            # is listening; TCP inbounds are additionally connected to.
            deadline = time.monotonic() + 15
            tcp_ports = [item['port'] for item in inbounds if item['protocol'] != 'hysteria']
            while True:
                if process.poll() is not None:
                    raise RuntimeError('Local Xray failed to start: ' + config.name)
                try:
                    if ' started' not in log_path.read_text(errors='replace'):
                        raise OSError('not started')
                    for port in tcp_ports:
                        with socket.create_connection(('127.0.0.1', port), timeout=1):
                            pass
                    break
                except OSError:
                    if time.monotonic() > deadline:
                        raise RuntimeError('Local Xray startup timed out')
                    time.sleep(.1)
            yield
        except Exception:
            log.flush(); log.seek(0)
            print(log.read()[-10000:], flush=True)
            raise
        finally:
            process.terminate()
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired: process.kill(); process.wait()


def main():
    reference = reference_binary()
    groups, names = selection()
    check_only = os.environ.get('TEAPOD_INTEROP_CHECK_ONLY') == '1'
    cli = pathlib.Path(os.environ.get('XRAY_RUST_CLI', ROOT / '.native/host-cli-0.8.1/xray-rust'))
    if check_only and not cli.exists():
        raise SystemExit(f'TEAPOD_INTEROP_CHECK_ONLY needs the xray-rust host CLI: {cli} (set XRAY_RUST_CLI)')
    adb = ['adb'] + (['-s', os.environ['ANDROID_SERIAL']] if os.environ.get('ANDROID_SERIAL') else [])
    fixture_path = '/data/local/tmp/teapod-vless-interop.json'
    workdir = os.environ.get('TEAPOD_INTEROP_WORKDIR')
    with (contextlib.nullcontext(workdir) if workdir else
          tempfile.TemporaryDirectory(prefix='teapod-vless-interop-')) as temp:
        directory = pathlib.Path(temp)
        directory.mkdir(parents=True, exist_ok=True)
        cert, key, pin = certificate(directory)
        with local_servers(cert, key) as ports:
            plan = Plan(reference, cert, key, pin, ports['tlsEchoPort'], ports['udpEchoPort'])
            plan_cases(plan, groups, names)
            source = directory / 'input.json'
            source.write_text(json.dumps(dict(cases=plan.cases, certificatePem=cert.read_text(), **ports)))
            config = directory / 'server.json'
            config.write_text(json.dumps(server_config(plan)))
            output = directory / 'clients.json'
            env = export_clients(source, output)
            if cli.exists():
                check_configs(reference, cli, directory, config, output)
            else:
                print(f'SKIP config check: no xray-rust CLI at {cli}', flush=True)
            if check_only:
                print(f'CHECKED: {len(plan.cases)} cases ({", ".join(sorted(groups))}), no device run', flush=True)
                return
            with reference_server(reference, config, directory / 'xray.log', plan.inbounds):
                try:
                    run(adb + ['push', str(output), fixture_path], capture_output=True)
                    flag = base64.b64encode(b'TEAPOD_CORE=rust').decode()
                    run(['./gradlew', ':xraymobile:connectedDebugAndroidTest', '--console=plain',
                         '-Pdart-defines=' + flag,
                         '-Pandroid.testInstrumentationRunnerArguments.class=org.xrayrust.mobile.VlessTransportInteropTest',
                         '-Pandroid.testInstrumentationRunnerArguments.interopConfig=' + fixture_path],
                        cwd=ROOT / 'android', env=env)
                    print(f'PASS: {len(plan.cases)} cases ({", ".join(sorted(groups))}): plain and '
                          'inner-TLS echo, SOCKS and TUN UDP checks, in-core and candidate outbound probes',
                          flush=True)
                finally:
                    subprocess.run(adb + ['shell', 'rm', '-f', fixture_path], capture_output=True)


if __name__ == '__main__':
    main()
