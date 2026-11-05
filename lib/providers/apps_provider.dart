import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_constants.dart';
import '../core/models/app_info.dart';
import 'settings_provider.dart';

final installedAppsProvider =
    FutureProvider<List<AppInfo>>((ref) async {
  const channel = MethodChannel(AppConstants.methodChannel);
  try {
    final result = await channel.invokeMethod<List>('getInstalledApps');
    if (result == null) return [];

    final settings = ref.read(settingsProvider).maybeWhen(data: (d) => d, orElse: () => null);
    final excluded = settings?.excludedPackages ?? {};

    return result.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      final pkg = map['packageName'] as String;
      return AppInfo(
        packageName: pkg,
        appName: map['appName'] as String? ?? pkg,
        isSystem: map['isSystem'] as bool? ?? false,
        isExcluded: excluded.contains(pkg),
      );
    }).toList()
      ..sort((a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));
  } on PlatformException {
    return [];
  }
});
