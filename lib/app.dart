import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ui/theme/app_theme.dart';
import 'ui/theme/app_colors.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/configs_screen.dart';
import 'ui/screens/logs_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'providers/config_provider.dart';
import 'providers/vpn_provider.dart';
import 'core/services/settings_service.dart';
import 'providers/settings_provider.dart';
import 'providers/update_provider.dart';
import 'providers/theme_provider.dart';

class TeapodApp extends StatelessWidget {
  const TeapodApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProviderScope(
      child: _TeapodMaterialApp(),
    );
  }
}

class _TeapodMaterialApp extends ConsumerWidget {
  const _TeapodMaterialApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final accent    = ref.watch(accentProvider);
    final fontScale = ref.watch(settingsProvider).maybeWhen(
      data: (s) => s.fontScale == FontScale.large ? 1.2 : 1.0,
      orElse: () => 1.0,
    );
    return MaterialApp(
      title: 'TeapodStream',
      theme:     AppTheme.build(Brightness.light, accent),
      darkTheme:  AppTheme.build(Brightness.dark, accent),
      themeMode: themeMode,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(
          textScaler: TextScaler.linear(fontScale),
        ),
        child: child!,
      ),
      home: const _AppShell(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ── App shell ─────────────────────────────────────────────────────

class _AppShell extends ConsumerStatefulWidget {
  const _AppShell();

  @override
  ConsumerState<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<_AppShell>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _autoConnectAttempted = false;

  static const _pages = [
    HomeScreen(),
    ConfigsScreen(),
    LogsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(vpnProvider.notifier).syncNativeState();
      if (_autoConnectAttempted) return;
      _autoConnectAttempted = true;
      _tryAutoConnect();
      _scheduleUpdateCheck();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(vpnProvider.notifier).syncNativeState();
    }
  }

  Future<void> _scheduleUpdateCheck() async {
    await Future.delayed(const Duration(seconds: 5));
    if (!mounted) return;
    final updateState = ref.read(updateProvider);
    if (updateState is UpdateIdle) {
      ref.read(updateProvider.notifier).checkForUpdate();
    }
  }

  Future<void> _tryAutoConnect() async {
    final settings = await ref.read(settingsProvider.future);
    if (!mounted || !settings.autoConnect) return;
    final configState = await ref.read(configProvider.future);
    if (!mounted || configState.activeConfig == null) return;
    final vpnState = ref.read(vpnProvider);
    if (!vpnState.isConnected && !vpnState.isConnecting) {
      await ref.read(vpnProvider.notifier).connect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final updateState = ref.watch(updateProvider);
    final hasUpdate = updateState is UpdateAvailable ||
        updateState is UpdateDownloading ||
        updateState is UpdateDownloaded;

    // Sync nav bar color with active theme
    final t = Theme.of(context).extension<TeapodTokens>()!;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness:
          Theme.of(context).brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
      systemNavigationBarColor: t.bg,
      systemNavigationBarIconBrightness:
          Theme.of(context).brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
    ));

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: _ConsoleTabBar(
        currentIndex: _currentIndex,
        hasUpdateBadge: hasUpdate,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}

// ── Custom console tab bar ────────────────────────────────────────

class _ConsoleTabBar extends ConsumerWidget {
  final int currentIndex;
  final bool hasUpdateBadge;
  final void Function(int) onTap;

  const _ConsoleTabBar({
    required this.currentIndex,
    required this.hasUpdateBadge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).extension<TeapodTokens>()!;

    final items = [
      _TabItem(icon: _TabIcon.shield,   label: 'VPN'),
      _TabItem(icon: _TabIcon.key,      label: 'Конфиги'),
      _TabItem(icon: _TabIcon.list,     label: 'Логи'),
      _TabItem(icon: _TabIcon.cog,      label: 'Настройки', badge: hasUpdateBadge),
    ];

    return Container(
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(top: BorderSide(color: t.line, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
          child: Row(
            children: items.asMap().entries.map((e) {
              final idx    = e.key;
              final item   = e.value;
              final active = idx == currentIndex;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(idx),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Active underline indicator
                      Container(
                        width: 28,
                        height: 2,
                        color: active ? t.accent : Colors.transparent,
                      ),
                      const SizedBox(height: 5),
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _SvgTabIcon(
                            icon: item.icon,
                            color: active ? t.accent : t.textMuted,
                          ),
                          if (item.badge)
                            Positioned(
                              right: -3,
                              top: -3,
                              child: Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: t.danger,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label.toUpperCase(),
                        style: AppTheme.mono(
                          size: 10,
                          color: active ? t.accent : t.textMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _TabItem {
  final _TabIcon icon;
  final String label;
  final bool badge;
  const _TabItem({required this.icon, required this.label, this.badge = false});
}

enum _TabIcon { shield, key, list, cog }

class _SvgTabIcon extends StatelessWidget {
  final _TabIcon icon;
  final Color color;
  const _SvgTabIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(20, 20),
      painter: _TabIconPainter(icon, color),
    );
  }
}

class _TabIconPainter extends CustomPainter {
  final _TabIcon icon;
  final Color color;
  const _TabIconPainter(this.icon, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final s = size.width / 24.0;
    canvas.scale(s, s);

    switch (icon) {
      case _TabIcon.shield:
        final path = Path()
          ..moveTo(12, 3)
          ..lineTo(20, 6)
          ..lineTo(20, 12)
          ..cubicTo(20, 16.5, 17, 20.5, 12, 22)
          ..cubicTo(7, 20.5, 4, 16.5, 4, 12)
          ..lineTo(4, 6)
          ..close();
        canvas.drawPath(path, paint);
        break;
      case _TabIcon.key:
        canvas.drawCircle(const Offset(8, 15), 4, paint);
        canvas.drawLine(const Offset(10.8, 12.2), const Offset(20, 3), paint);
        canvas.drawLine(const Offset(17, 6), const Offset(20, 9), paint);
        canvas.drawLine(const Offset(15, 8), const Offset(17, 10), paint);
        break;
      case _TabIcon.list:
        for (final y in [6.0, 12.0, 18.0]) {
          canvas.drawLine(Offset(8, y), Offset(20, y), paint);
          canvas.drawCircle(Offset(4, y), 0.5,
              Paint()..color = color..style = PaintingStyle.fill);
        }
        break;
      case _TabIcon.cog:
        canvas.drawCircle(const Offset(12, 12), 3, paint);
        for (var i = 0; i < 8; i++) {
          final angle = i * math.pi / 4;
          final c = math.cos(angle);
          final s = math.sin(angle);
          canvas.drawLine(
            Offset(12 + c * 5, 12 + s * 5),
            Offset(12 + c * 9, 12 + s * 9),
            paint,
          );
        }
        break;
    }
  }

  @override
  bool shouldRepaint(_TabIconPainter old) => old.color != color || old.icon != icon;
}
