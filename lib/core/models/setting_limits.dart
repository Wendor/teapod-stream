/// Inclusive limits of a numeric setting: the settings screens and `fromJson` clamp to them.
typedef SettingLimits = ({int min, int max});

extension SettingLimitsClamp on SettingLimits {
  int clamp(int value) => value < min ? min : (value > max ? max : value);
}
