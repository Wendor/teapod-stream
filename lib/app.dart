import 'dart:async';
import 'dart:math' as math;
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/l10n.dart';
import 'ui/theme/app_theme.dart';
import 'ui/theme/app_colors.dart';
import 'ui/screens/home/home_screen.dart';
import 'ui/screens/configs/configs_screen.dart';
import 'ui/screens/routing/routing_screen.dart';
import 'ui/screens/settings/settings_screen.dart';
import 'core/models/app_settings.dart';
import 'providers/settings_provider.dart';
import 'providers/update_provider.dart';
import 'providers/app_lifecycle_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/locale_provider.dart';
import 'ui/deeplink_handler.dart';
import 'protocols/xray/xray_engine.dart';
import 'ui/theme/app_text_scaler.dart';
import 'itest/itest_agent.dart';
import 'itest/itest_protocol.dart';

class TeapodApp extends StatelessWidget {
  const TeapodApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProviderScope(child: _TeapodMaterialApp());
  }
}

class _TeapodMaterialApp extends ConsumerWidget {
  const _TeapodMaterialApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final accent = ref.watch(accentProvider);
    final locale = ref.watch(localeProvider);
    final fontScale = ref
        .watch(settingsProvider)
        .maybeWhen(data: (s) => s.fontScale == FontScale.large ? 1.2 : 1.0, orElse: () => 1.0);
    return MaterialApp(
      title: 'TeapodStream',
      theme: AppTheme.build(Brightness.light, accent),
      darkTheme: AppTheme.build(Brightness.dark, accent),
      themeMode: themeMode,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        // ignore: deprecated_member_use
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        // ignore: deprecated_member_use
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (ctx, child) {
        L10n.current = ctx.l10n;
        return MediaQuery(
          data: MediaQuery.of(ctx).copyWith(textScaler: appTextScaler(MediaQuery.textScalerOf(ctx), fontScale)),
          child: child!,
        );
      },
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

class _AppShellState extends ConsumerState<_AppShell> with WidgetsBindingObserver {
  StreamSubscription<dynamic>? _deeplinkSubscription;

  static const _pages = [HomeScreen(), ConfigsScreen(), RoutingScreen(), SettingsScreen()];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (kItest) ItestAgent.start(ProviderScope.containerOf(context, listen: false));
      ref.read(appLifecycleProvider.notifier).start();
    });

    _deeplinkSubscription = XrayEngine.events.listen(_handleEvent);
  }

  @override
  void dispose() {
    _deeplinkSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lifecycle = ref.read(appLifecycleProvider.notifier);
    if (state == AppLifecycleState.resumed) {
      lifecycle.resumed();
    } else if (state == AppLifecycleState.paused) {
      lifecycle.paused();
    }
  }

  void _handleEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['type'];
    if (type != 'deeplink') return;
    final uri = event['uri'] as String?;
    if (uri == null || !mounted) return;
    DeeplinkHandler(context, ref).handleUri(uri);
  }

  @override
  Widget build(BuildContext context) {
    // Its listeners (new configs pinged, the chart on the home tab) live as long as the shell.
    ref.watch(appLifecycleProvider);

    final currentIndex = ref.watch(tabIndexProvider);
    // The system bars follow the theme: the framework applies the region's style when it changes, not on every build.
    final theme = Theme.of(context);
    final icons = theme.brightness == Brightness.dark ? Brightness.light : Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: icons,
        systemNavigationBarColor: theme.extension<TeapodTokens>()!.bg,
        systemNavigationBarIconBrightness: icons,
      ),
      child: Scaffold(
        body: IndexedStack(index: currentIndex, children: _pages),
        bottomNavigationBar: _ConsoleTabBar(
          currentIndex: currentIndex,
          onTap: (i) => ref.read(tabIndexProvider.notifier).set(i),
        ),
      ),
    );
  }
}

// ── Custom console tab bar ────────────────────────────────────────

class _ConsoleTabBar extends ConsumerWidget {
  final int currentIndex;
  final void Function(int) onTap;

  const _ConsoleTabBar({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).extension<TeapodTokens>()!;

    final update = ref.watch(updateProvider);
    final hasUpdateBadge = update is UpdateAvailable || update is UpdateDownloading || update is UpdateDownloaded;
    final l = context.l10n;
    final items = [
      _TabItem(icon: _TabIcon.shield, label: 'VPN'),
      _TabItem(icon: _TabIcon.key, label: l.tabConfigs),
      _TabItem(icon: _TabIcon.route, label: l.tabRouting),
      _TabItem(icon: _TabIcon.cog, label: l.tabSettings, badge: hasUpdateBadge),
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
              final idx = e.key;
              final item = e.value;
              final active = idx == currentIndex;
              return Expanded(
                child: Semantics(
                  label: item.label,
                  button: true,
                  selected: active,
                  child: GestureDetector(
                    onTap: () => onTap(idx),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Active underline indicator
                        Container(width: 28, height: 2, color: active ? t.accent : Colors.transparent),
                        const SizedBox(height: 5),
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            _SvgTabIcon(icon: item.icon, color: active ? t.accent : t.textMuted),
                            if (item.badge)
                              Positioned(
                                right: -3,
                                top: -3,
                                child: Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(color: t.danger, shape: BoxShape.circle),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.label.toUpperCase(),
                          style: AppTheme.mono(size: 10, color: active ? t.accent : t.textMuted, letterSpacing: 0.5),
                        ),
                      ],
                    ),
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

enum _TabIcon { shield, key, route, cog }

class _SvgTabIcon extends StatelessWidget {
  final _TabIcon icon;
  final Color color;
  const _SvgTabIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(20, 20), painter: _TabIconPainter(icon, color));
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
      case _TabIcon.route:
        final route = Path()
          ..moveTo(4, 18)
          ..lineTo(10, 18)
          ..lineTo(14, 6)
          ..lineTo(20, 6);
        canvas.drawPath(route, paint);
        canvas.drawLine(const Offset(17, 3), const Offset(20, 6), paint);
        canvas.drawLine(const Offset(20, 6), const Offset(17, 9), paint);
        canvas.drawCircle(const Offset(4, 18), 1.4, paint);
        break;
      case _TabIcon.cog:
        canvas.drawCircle(const Offset(12, 12), 3, paint);
        for (var i = 0; i < 8; i++) {
          final angle = i * math.pi / 4;
          final c = math.cos(angle);
          final s = math.sin(angle);
          canvas.drawLine(Offset(12 + c * 5, 12 + s * 5), Offset(12 + c * 9, 12 + s * 9), paint);
        }
        break;
    }
  }

  @override
  bool shouldRepaint(_TabIconPainter old) => old.color != color || old.icon != icon;
}
