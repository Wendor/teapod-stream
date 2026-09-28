import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'app.dart';
import 'core/constants/app_constants.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // App version for the subscription User-Agent (single source of truth: pubspec).
  try {
    AppConstants.appVersion = (await PackageInfo.fromPlatform()).version;
  } catch (_) {
    // Non-critical: UA will fall back to 'unknown'
  }

  // Fetch xray-core version early so it's available in the subscription User-Agent.
  try {
    const channel = MethodChannel(AppConstants.methodChannel);
    final versions = await channel.invokeMethod<Map>('getBinaryVersions');
    final xray = versions?['xray'] as String?;
    if (xray != null && xray.isNotEmpty && xray != 'Error' && xray != '—') {
      AppConstants.xrayCoreVersion = xray;
    }
  } catch (_) {
    // Non-critical: UA will fall back to 'unknown'
  }

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF161A22),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const TeapodApp());
}
