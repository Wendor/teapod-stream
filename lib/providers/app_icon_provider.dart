import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/platform_service.dart';

final _iconCache = <String, Uint8List>{};

final appIconProvider = FutureProvider.family<Uint8List?, String>((ref, packageName) async {
  if (_iconCache.containsKey(packageName)) return _iconCache[packageName];
  try {
    final bytes = await ref.read(platformServiceProvider).appIcon(packageName);
    if (bytes != null) _iconCache[packageName] = bytes;
    return bytes;
  } on PlatformException {
    return null;
  }
});
