class AppInfo {
  final String packageName;
  final String appName;
  final bool isSystem;
  final bool isExcluded;

  const AppInfo({required this.packageName, required this.appName, this.isSystem = false, this.isExcluded = false});

  AppInfo copyWith({bool? isSystem, bool? isExcluded}) => AppInfo(
    packageName: packageName,
    appName: appName,
    isSystem: isSystem ?? this.isSystem,
    isExcluded: isExcluded ?? this.isExcluded,
  );
}
