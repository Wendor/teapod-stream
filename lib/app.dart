import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ui/theme/app_theme.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/configs_screen.dart';
import 'ui/screens/logs_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'providers/config_provider.dart';
import 'providers/vpn_provider.dart';
import 'providers/settings_provider.dart';

class TeapodApp extends StatelessWidget {
  const TeapodApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        title: 'TeapodStream',
        theme: AppTheme.dark,
        home: const _AppShell(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class _AppShell extends ConsumerStatefulWidget {
  const _AppShell();

  @override
  ConsumerState<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<_AppShell> with WidgetsBindingObserver {
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
      if (_autoConnectAttempted) return;
      _autoConnectAttempted = true;
      _tryAutoConnect();
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
      // Sync VPN state with native service when app resumes
      ref.read(vpnProvider.notifier).syncNativeState();
    }
  }

  Future<void> _tryAutoConnect() async {
    // Give providers time to initialize
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    final settings = ref.read(settingsProvider).maybeWhen(
      data: (d) => d,
      orElse: () => null,
    );
    if (settings == null || !settings.autoConnect) return;

    final configState = ref.read(configProvider).maybeWhen(
      data: (d) => d,
      orElse: () => null,
    );
    if (configState?.activeConfig == null) return;

    final vpnState = ref.read(vpnProvider);
    if (!vpnState.isConnected && !vpnState.isConnecting) {
      await ref.read(vpnProvider.notifier).connect();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.shield_outlined),
            selectedIcon: Icon(Icons.shield_rounded),
            label: 'VPN',
          ),
          NavigationDestination(
            icon: Icon(Icons.vpn_key_outlined),
            selectedIcon: Icon(Icons.vpn_key_rounded),
            label: 'Конфиги',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt_rounded),
            label: 'Логи',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Настройки',
          ),
        ],
      ),
    );
  }
}
