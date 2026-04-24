import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/app_info.dart';
import '../../core/services/settings_service.dart';
import '../../providers/app_icon_provider.dart';
import '../../providers/apps_provider.dart';
import '../../providers/settings_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class SplitTunnelScreen extends ConsumerStatefulWidget {
  const SplitTunnelScreen({super.key});

  @override
  ConsumerState<SplitTunnelScreen> createState() => _SplitTunnelScreenState();
}

class _SplitTunnelScreenState extends ConsumerState<SplitTunnelScreen> {
  String _search = '';
  bool _hideSystemApps = true;

  void _togglePackage(String pkg, bool isOnlySelected) {
    final settings = ref.read(settingsProvider).maybeWhen(
      data: (d) => d,
      orElse: () => null,
    );
    if (settings == null) return;

    if (isOnlySelected) {
      final newIncluded = Set<String>.from(settings.includedPackages);
      newIncluded.contains(pkg) ? newIncluded.remove(pkg) : newIncluded.add(pkg);
      ref.read(settingsProvider.notifier).save(
            settings.copyWith(includedPackages: newIncluded));
    } else {
      final newExcluded = Set<String>.from(settings.excludedPackages);
      newExcluded.contains(pkg) ? newExcluded.remove(pkg) : newExcluded.add(pkg);
      ref.read(settingsProvider.notifier).save(
            settings.copyWith(excludedPackages: newExcluded));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    final appsAsync = ref.watch(installedAppsProvider);
    final settings = ref.watch(settingsProvider).maybeWhen(
      data: (d) => d,
      orElse: () => null,
    );
    final isOnlySelected = settings?.vpnMode == VpnMode.onlySelected;
    final packages = isOnlySelected
        ? (settings?.includedPackages ?? {})
        : (settings?.excludedPackages ?? {});

    final modeLabel = isOnlySelected ? 'ONLY' : 'EXCEPT';
    final countStr = packages.length.toString().padLeft(2, '0');

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
                  Text('teapod.stream // apps',
                      style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
                  Text('sel[$countStr]',
                      style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
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
                    Text('settings',
                        style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
                    const SizedBox(width: 6),
                    Text('/', style: AppTheme.mono(size: 10, color: t.textMuted)),
                    const SizedBox(width: 6),
                    Text('split-tunnel',
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
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ПРИЛОЖЕНИЯ · SPLIT-TUNNEL',
                                style: AppTheme.mono(
                                    size: 10, color: t.textMuted, letterSpacing: 1.5)),
                            const SizedBox(height: 8),
                            Text('APPS',
                                style: AppTheme.sans(
                                    size: 30,
                                    weight: FontWeight.w500,
                                    color: t.text,
                                    letterSpacing: -1,
                                    height: 1)),
                            const SizedBox(height: 6),
                            Text(
                              isOnlySelected
                                  ? '${packages.length} выбрано · только через VPN'
                                  : '${packages.length} исключено · остальное через VPN',
                              style: AppTheme.mono(
                                  size: 11, color: t.textDim, letterSpacing: 0.5),
                            ),
                          ],
                        ),
                        // Mode badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(border: Border.all(color: t.accent)),
                          child: Text(modeLabel,
                              style: AppTheme.mono(
                                  size: 11, color: t.accent, letterSpacing: 1)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── Mode selector ─────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              decoration:
                  BoxDecoration(border: Border(bottom: BorderSide(color: t.lineSoft))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Режим VPN', style: AppTheme.sans(size: 14, color: t.text)),
                  Container(
                    decoration: BoxDecoration(border: Border.all(color: t.line)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (mode, lab) in [
                          (VpnMode.onlySelected, 'ТОЛЬКО'),
                          (VpnMode.allExcept, 'КРОМЕ'),
                        ]) ...[
                          GestureDetector(
                            onTap: () {
                              if (settings != null) {
                                ref.read(settingsProvider.notifier).save(
                                      settings.copyWith(vpnMode: mode));
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: settings?.vpnMode == mode
                                    ? t.accentSoft
                                    : Colors.transparent,
                                border: mode == VpnMode.onlySelected
                                    ? Border(right: BorderSide(color: t.line))
                                    : null,
                              ),
                              child: Text(lab,
                                  style: AppTheme.mono(
                                      size: 11,
                                      color: settings?.vpnMode == mode
                                          ? t.accent
                                          : t.textDim,
                                      letterSpacing: 0.5)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── Search ────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              decoration:
                  BoxDecoration(border: Border(bottom: BorderSide(color: t.lineSoft))),
              child: Container(
                decoration: BoxDecoration(border: Border.all(color: t.line)),
                child: TextField(
                  style: AppTheme.mono(size: 12, color: t.text),
                  onChanged: (v) => setState(() => _search = v.toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'поиск приложений...',
                    hintStyle: AppTheme.mono(size: 11, color: t.textMuted),
                    prefixIcon: Icon(Icons.search_rounded, size: 16, color: t.textMuted),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            // ── Hide system apps toggle ────────────────────────────
            GestureDetector(
              onTap: () => setState(() => _hideSystemApps = !_hideSystemApps),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                decoration:
                    BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Скрыть системные приложения',
                        style: AppTheme.sans(size: 13, color: t.text)),
                    _SquareCheckbox(t: t, value: _hideSystemApps),
                  ],
                ),
              ),
            ),
            // ── App list ──────────────────────────────────────────
            Expanded(
              child: appsAsync.when(
                loading: () =>
                    Center(child: CircularProgressIndicator(color: t.accent, strokeWidth: 1.5)),
                error: (e, _) => Center(
                  child: Text('Ошибка: $e',
                      style: AppTheme.mono(size: 12, color: t.danger)),
                ),
                data: (apps) {
                  var filtered = _search.isEmpty
                      ? apps
                      : apps
                          .where((a) =>
                              a.appName.toLowerCase().contains(_search) ||
                              a.packageName.toLowerCase().contains(_search))
                          .toList();

                  if (_hideSystemApps) {
                    filtered = filtered.where((a) => !a.isSystem).toList();
                  }

                  filtered.sort((a, b) {
                    final aSelected = packages.contains(a.packageName);
                    final bSelected = packages.contains(b.packageName);
                    if (aSelected != bSelected) return aSelected ? -1 : 1;
                    return a.appName.compareTo(b.appName);
                  });

                  if (filtered.isEmpty) {
                    return Center(
                      child: Text('[ нет приложений ]',
                          style: AppTheme.mono(
                              size: 12, color: t.textMuted, letterSpacing: 1)),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final app = filtered[i];
                      final isSelected = packages.contains(app.packageName);
                      return _AppRow(
                        t: t,
                        app: app,
                        isSelected: isSelected,
                        isOnlySelected: isOnlySelected,
                        onToggle: () => _togglePackage(app.packageName, isOnlySelected),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── App row ───────────────────────────────────────────────────────

class _AppRow extends ConsumerWidget {
  final TeapodTokens t;
  final AppInfo app;
  final bool isSelected;
  final bool isOnlySelected;
  final VoidCallback onToggle;

  const _AppRow({
    required this.t,
    required this.app,
    required this.isSelected,
    required this.isOnlySelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iconAsync = ref.watch(appIconProvider(app.packageName));

    return GestureDetector(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.lineSoft))),
        child: Row(
          children: [
            // Square checkbox
            Container(
              width: 18, height: 18,
              decoration: BoxDecoration(
                border: Border.all(color: isSelected ? t.accent : t.line),
                color: isSelected ? t.accent : Colors.transparent,
              ),
              child: isSelected
                  ? Icon(Icons.check, size: 12, color: t.bg)
                  : null,
            ),
            const SizedBox(width: 14),
            // App icon
            SizedBox(
              width: 36, height: 36,
              child: iconAsync.when(
                loading: () => _FallbackIcon(t: t, isSelected: isSelected),
                error: (_, _) => _FallbackIcon(t: t, isSelected: isSelected),
                data: (Uint8List? bytes) => bytes != null
                    ? Image.memory(bytes, width: 36, height: 36,
                        errorBuilder: (_, _, _) =>
                            _FallbackIcon(t: t, isSelected: isSelected))
                    : _FallbackIcon(t: t, isSelected: isSelected),
              ),
            ),
            const SizedBox(width: 12),
            // Labels
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(app.appName,
                      style: AppTheme.sans(
                          size: 13,
                          color: isSelected ? t.text : t.textDim,
                          weight: isSelected ? FontWeight.w500 : FontWeight.normal),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(app.packageName,
                      style: AppTheme.mono(
                          size: 10, color: t.textMuted, letterSpacing: 0.3),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FallbackIcon extends StatelessWidget {
  final TeapodTokens t;
  final bool isSelected;
  const _FallbackIcon({required this.t, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isSelected ? t.accentSoft : t.bgSunken,
      child: Icon(Icons.apps_rounded,
          size: 18, color: isSelected ? t.accent : t.textMuted),
    );
  }
}

// ── Square checkbox ───────────────────────────────────────────────

class _SquareCheckbox extends StatelessWidget {
  final TeapodTokens t;
  final bool value;
  const _SquareCheckbox({required this.t, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18, height: 18,
      decoration: BoxDecoration(
        border: Border.all(color: value ? t.accent : t.line),
        color: value ? t.accent : Colors.transparent,
      ),
      child: value ? Icon(Icons.check, size: 12, color: t.bg) : null,
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
