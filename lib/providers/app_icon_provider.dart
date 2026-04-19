import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_constants.dart';

final _iconCache = <String, Uint8List>{};

final appIconProvider = FutureProvider.family<Uint8List?, String>((ref, packageName) async {
  if (_iconCache.containsKey(packageName)) return _iconCache[packageName];
  const channel = MethodChannel(AppConstants.methodChannel);
  try {
    final bytes = await channel.invokeMethod<Uint8List>('getAppIcon', {'packageName': packageName});
    if (bytes != null) _iconCache[packageName] = bytes;
    return bytes;
  } on PlatformException {
    return null;
  }
});
