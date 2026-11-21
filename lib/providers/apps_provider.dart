import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/models/app_info.dart';
import 'settings_provider.dart';
import '../core/services/platform_service.dart';

final installedAppsProvider = FutureProvider<List<AppInfo>>((ref) async {
  try {
    final result = await ref.read(platformServiceProvider).installedApps();

    final settings = ref.read(settingsProvider).maybeWhen(data: (d) => d, orElse: () => null);
    final excluded = settings?.excludedPackages ?? {};

    return result.map((map) {
      final pkg = map['packageName'] as String;
      return AppInfo(
        packageName: pkg,
        appName: map['appName'] as String? ?? pkg,
        isSystem: map['isSystem'] as bool? ?? false,
        isExcluded: excluded.contains(pkg),
      );
    }).toList()..sort((a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));
  } on PlatformException {
    return [];
  }
});
