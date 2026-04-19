import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/app_info.dart';
import '../../core/services/settings_service.dart';
import '../../providers/app_icon_provider.dart';
import '../../providers/apps_provider.dart';
import '../../providers/settings_provider.dart';
import '../theme/app_colors.dart';

class SplitTunnelScreen extends ConsumerStatefulWidget {
  const SplitTunnelScreen({super.key});

  @override
  ConsumerState<SplitTunnelScreen> createState() => _SplitTunnelScreenState();
}

class _SplitTunnelScreenState extends ConsumerState<SplitTunnelScreen> {
  String _search = '';
  bool _hideSystemApps = true;

  void _togglePackage(String pkg, bool isOnlySelected, WidgetRef ref) {
    final settings = ref.read(settingsProvider).maybeWhen(
      data: (d) => d,
      orElse: () => null,
    );
    if (settings == null) return;

    if (isOnlySelected) {
      final newIncluded = Set<String>.from(settings.includedPackages);
      if (newIncluded.contains(pkg)) {
        newIncluded.remove(pkg);
      } else {
        newIncluded.add(pkg);
      }
      ref.read(settingsProvider.notifier).save(
        settings.copyWith(includedPackages: newIncluded),
      );
    } else {
      final newExcluded = Set<String>.from(settings.excludedPackages);
      if (newExcluded.contains(pkg)) {
        newExcluded.remove(pkg);
      } else {
        newExcluded.add(pkg);
      }
      ref.read(settingsProvider.notifier).save(
        settings.copyWith(excludedPackages: newExcluded),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appsAsync = ref.watch(installedAppsProvider);
    final settings = ref.watch(settingsProvider).maybeWhen(data: (d) => d, orElse: () => null);
    final isOnlySelected = settings?.vpnMode == VpnMode.onlySelected;
    final packages = isOnlySelected
        ? (settings?.includedPackages ?? {})
        : (settings?.excludedPackages ?? {});

    return Scaffold(
      appBar: AppBar(
        title: Text(isOnlySelected ? 'Выбранные приложения' : 'Исключения'),
        actions: [
          if (packages.isNotEmpty)
            Center(
              child: Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryDim.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${packages.length}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Mode toggle
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.tune_rounded, color: AppColors.primary, size: 18),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Режим VPN',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SegmentedButton<VpnMode>(
                  segments: const [
                    ButtonSegment(
                      value: VpnMode.onlySelected,
                      label: Text('Выбранные'),
                      icon: Icon(Icons.check_circle_rounded, size: 16),
                    ),
                    ButtonSegment(
                      value: VpnMode.allExcept,
                      label: Text('Все, кроме'),
                      icon: Icon(Icons.block_rounded, size: 16),
                    ),
                  ],
                  selected: {settings?.vpnMode ?? VpnMode.onlySelected},
                  onSelectionChanged: (modes) {
                    if (modes.isNotEmpty) {
                      ref.read(settingsProvider.notifier).save(
                        settings!.copyWith(vpnMode: modes.first),
                      );
                    }
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  isOnlySelected
                      ? 'Только выбранные приложения пойдут через VPN. Остальные — напрямую.'
                      : 'Весь трафик идёт через VPN, кроме выбранных приложений.',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // Search and system apps filter
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Поиск приложений...',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
            child: Row(
              children: [
                Checkbox(
                  value: _hideSystemApps,
                  onChanged: (v) => setState(() => _hideSystemApps = v ?? true),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                GestureDetector(
                  onTap: () => setState(() => _hideSystemApps = !_hideSystemApps),
                  child: const Text(
                    'Скрыть системные приложения',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: appsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        color: AppColors.error, size: 40),
                    const SizedBox(height: 12),
                    Text('Не удалось загрузить приложения: $e'),
                  ],
                ),
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

                // Отмеченные приложения — в начало списка
                filtered.sort((a, b) {
                  final aSelected = packages.contains(a.packageName);
                  final bSelected = packages.contains(b.packageName);
                  if (aSelected != bSelected) return aSelected ? -1 : 1;
                  return a.appName.compareTo(b.appName);
                });

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final app = filtered[i];
                    final isIncluded = packages.contains(app.packageName);
                    return _AppListTile(
                      app: app.copyWith(isExcluded: isIncluded),
                      isOnlySelected: isOnlySelected,
                      onToggle: () => _togglePackage(app.packageName, isOnlySelected, ref),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AppListTile extends ConsumerWidget {
  final AppInfo app;
  final VoidCallback onToggle;
  final bool isOnlySelected;

  const _AppListTile({
    required this.app,
    required this.onToggle,
    required this.isOnlySelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iconAsync = ref.watch(appIconProvider(app.packageName));

    return ListTile(
      title: Text(
        app.appName,
        style: TextStyle(
          color: app.isExcluded ? AppColors.textPrimary : AppColors.textSecondary,
          fontWeight: app.isExcluded ? FontWeight.w500 : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        app.packageName,
        style: const TextStyle(fontSize: 11, color: AppColors.textDisabled),
      ),
      leading: Stack(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: iconAsync.when(
                loading: () => _FallbackIcon(isExcluded: app.isExcluded, isOnlySelected: isOnlySelected),
                error: (_, _) => _FallbackIcon(isExcluded: app.isExcluded, isOnlySelected: isOnlySelected),
                data: (Uint8List? bytes) => bytes != null
                    ? Image.memory(
                        bytes,
                        width: 40,
                        height: 40,
                        errorBuilder: (_, _, _) =>
                            _FallbackIcon(isExcluded: app.isExcluded, isOnlySelected: isOnlySelected),
                      )
                    : _FallbackIcon(isExcluded: app.isExcluded, isOnlySelected: isOnlySelected),
              ),
            ),
          ),
          if (app.isExcluded)
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: isOnlySelected ? AppColors.connected : AppColors.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 1.5),
                ),
                child: Icon(
                  isOnlySelected ? Icons.check_rounded : Icons.block_rounded,
                  size: 12,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
      trailing: Switch(
        value: app.isExcluded,
        onChanged: (_) => onToggle(),
      ),
      onTap: onToggle,
    );
  }
}

class _FallbackIcon extends StatelessWidget {
  final bool isExcluded;
  final bool isOnlySelected;
  const _FallbackIcon({required this.isExcluded, required this.isOnlySelected});

  @override
  Widget build(BuildContext context) {
    final activeColor = isOnlySelected ? AppColors.connected : AppColors.error;
    return Container(
      decoration: BoxDecoration(
        color: isExcluded
            ? activeColor.withValues(alpha: 0.1)
            : AppColors.surfaceHighlight,
      ),
      child: Icon(
        Icons.apps_rounded,
        color: isExcluded ? activeColor : AppColors.textDisabled,
        size: 20,
      ),
    );
  }
}
