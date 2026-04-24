import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/subscription_service.dart';
import '../../protocols/xray/vless_parser.dart';
import '../../providers/config_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'qr_scan_screen.dart';

class AddConfigScreen extends ConsumerStatefulWidget {
  const AddConfigScreen({super.key});

  @override
  ConsumerState<AddConfigScreen> createState() => _AddConfigScreenState();
}

class _AddConfigScreenState extends ConsumerState<AddConfigScreen> {
  final _uriController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _uriController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<TeapodTokens>()!;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Header strip ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('teapod.stream // add',
                      style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
                  GestureDetector(
                    onTap: _openQrScan,
                    child: Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(border: Border.all(color: t.line)),
                      child: Icon(Icons.qr_code_scanner_rounded, size: 14, color: t.textDim),
                    ),
                  ),
                ],
              ),
            ),
            // ── Breadcrumb ────────────────────────────────────────
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                decoration:
                    BoxDecoration(border: Border(bottom: BorderSide(color: t.lineSoft))),
                child: Row(
                  children: [
                    Text('‹', style: AppTheme.mono(size: 12, color: t.textMuted)),
                    const SizedBox(width: 8),
                    Text('configs',
                        style:
                            AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
                    const SizedBox(width: 6),
                    Text('/', style: AppTheme.mono(size: 10, color: t.textMuted)),
                    const SizedBox(width: 6),
                    Text('add',
                        style: AppTheme.mono(size: 10, color: t.text, letterSpacing: 1)),
                  ],
                ),
              ),
            ),
            // ── Hero panel ────────────────────────────────────────
            Container(
              width: double.infinity,
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
              child: Stack(
                children: [
                  _CornerTicks(t: t),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('КОНФИГУРАЦИЯ · НОВЫЙ ПРОФИЛЬ',
                            style: AppTheme.mono(
                                size: 10, color: t.textMuted, letterSpacing: 1.5)),
                        const SizedBox(height: 8),
                        Text('ADD CONFIG',
                            style: AppTheme.sans(
                                size: 30,
                                weight: FontWeight.w500,
                                color: t.text,
                                letterSpacing: -1,
                                height: 1)),
                        const SizedBox(height: 6),
                        Text('vless · vmess · trojan · ss · hy2 · subscription',
                            style: AppTheme.mono(
                                size: 11, color: t.textDim, letterSpacing: 0.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── Body ─────────────────────────────────────────────
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                          color: t.accent, strokeWidth: 1.5))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                      children: [
                        // Input field
                        Container(
                          decoration:
                              BoxDecoration(border: Border.all(color: t.line)),
                          child: TextField(
                            controller: _uriController,
                            maxLines: 6,
                            style: AppTheme.mono(size: 12, color: t.text),
                            decoration: InputDecoration(
                              hintText:
                                  'vless://uuid@host:port?...\nvmess://base64\ntrojan://pass@host:port\nhttps://example.com/sub',
                              hintStyle:
                                  AppTheme.mono(size: 11, color: t.textMuted),
                              contentPadding: const EdgeInsets.all(14),
                              isDense: true,
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            color: t.danger.withAlpha(0x1A),
                            child: Text(_error!,
                                style: AppTheme.mono(
                                    size: 11,
                                    color: t.danger,
                                    letterSpacing: 0.5)),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: _loading ? null : _pasteFromClipboard,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 13),
                                  decoration: BoxDecoration(
                                      border: Border.all(color: t.line)),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.paste_rounded,
                                          size: 14, color: t.textDim),
                                      const SizedBox(width: 8),
                                      Text('ВСТАВИТЬ',
                                          style: AppTheme.mono(
                                              size: 11,
                                              color: t.textDim,
                                              letterSpacing: 1)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: GestureDetector(
                                onTap: _loading ? null : _import,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 13),
                                  color: t.accent,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check_rounded,
                                          size: 14, color: t.bg),
                                      const SizedBox(width: 8),
                                      Text('ДОБАВИТЬ',
                                          style: AppTheme.mono(
                                              size: 11,
                                              color: t.bg,
                                              letterSpacing: 1)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _openQrScan() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    ).then((value) {
      if (value != null && value is String) {
        setState(() => _uriController.text = value);
        _processUri(value);
      }
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      _uriController.text = data.text!;
      await _import();
    }
  }

  Future<void> _import() async {
    final text = _uriController.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Введите URL');
      return;
    }
    await _processUri(text);
  }

  Future<void> _processUri(String uri, {bool allowSelfSigned = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final parsed = Uri.parse(uri);

      if (parsed.scheme == 'http' || parsed.scheme == 'https') {
        await ref.read(configProvider.notifier).addSubscriptionFromUrl(
              uri,
              allowSelfSigned: allowSelfSigned,
            );
        if (mounted) Navigator.pop(context);
      } else {
        final config = VlessParser.parseUri(uri);
        if (config != null) {
          await ref.read(configProvider.notifier).addConfig(config);
          await ref.read(configProvider.notifier).setActiveConfig(config.id);
          if (mounted) Navigator.pop(context);
          return;
        }
        setState(() => _error =
            'Не удалось распознать конфигурацию. Поддерживаются: vless://, vmess://, trojan://, ss://');
      }
    } on UntrustedCertificateException catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      final confirmed = await _showUntrustedCertDialog(e);
      if (confirmed == true && mounted) {
        await _processUri(uri, allowSelfSigned: true);
      }
      return;
    } catch (e) {
      setState(() => _error = 'Ошибка: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool?> _showUntrustedCertDialog(UntrustedCertificateException e) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.bgElev,
        title: Text('Ненадёжный сертификат',
            style: AppTheme.sans(size: 16, color: t.text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Сервер использует самоподписанный сертификат. '
              'Соединение может быть небезопасным.',
              style: AppTheme.sans(size: 13, color: t.textDim),
            ),
            const SizedBox(height: 12),
            Text('Сервер: ${e.host}',
                style: AppTheme.mono(size: 11, color: t.textDim)),
            Text('Субъект: ${e.subject}',
                style: AppTheme.mono(size: 11, color: t.textDim)),
            Text('Издатель: ${e.issuer}',
                style: AppTheme.mono(size: 11, color: t.textDim)),
            const SizedBox(height: 12),
            Text('Продолжить всё равно?',
                style: AppTheme.sans(size: 13, color: t.text)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                Text('Отмена', style: AppTheme.mono(size: 12, color: t.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                Text('Продолжить', style: AppTheme.mono(size: 12, color: t.danger)),
          ),
        ],
      ),
    );
  }
}

// ── Corner ticks ──────────────────────────────────────────────────

class _CornerTicks extends StatelessWidget {
  final TeapodTokens t;
  const _CornerTicks({required this.t});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(top: 6, left: 6,    child: _Tick(color: t.textMuted, tl: true)),
            Positioned(top: 6, right: 6,   child: _Tick(color: t.textMuted, tr: true)),
            Positioned(bottom: 6, left: 6,  child: _Tick(color: t.textMuted, bl: true)),
            Positioned(bottom: 6, right: 6, child: _Tick(color: t.textMuted, br: true)),
          ],
        ),
      ),
    );
  }
}

class _Tick extends StatelessWidget {
  final Color color;
  final bool tl, tr, bl, br;
  const _Tick({required this.color, this.tl=false, this.tr=false, this.bl=false, this.br=false});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(8, 8), painter: _TickPainter(color, tl, tr, bl, br));
}

class _TickPainter extends CustomPainter {
  final Color color;
  final bool tl, tr, bl, br;
  const _TickPainter(this.color, this.tl, this.tr, this.bl, this.br);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..strokeWidth = 1..style = PaintingStyle.stroke;
    final w = size.width; final h = size.height;
    if (tl) { canvas.drawLine(Offset.zero, Offset(w, 0), p); canvas.drawLine(Offset.zero, Offset(0, h), p); }
    if (tr) { canvas.drawLine(const Offset(0,0), Offset(w, 0), p); canvas.drawLine(Offset(w,0), Offset(w, h), p); }
    if (bl) { canvas.drawLine(Offset(0,h), Offset(w, h), p); canvas.drawLine(const Offset(0,0), Offset(0, h), p); }
    if (br) { canvas.drawLine(Offset(0,h), Offset(w, h), p); canvas.drawLine(Offset(w,0), Offset(w, h), p); }
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.color != color;
}
