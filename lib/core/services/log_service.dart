import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_constants.dart';
import '../models/vpn_log_entry.dart';

class _CircularBuffer {
  final List<VpnLogEntry?> _buffer;
  int _head = 0;
  int _count = 0;

  _CircularBuffer(int capacity) : _buffer = List<VpnLogEntry?>.filled(capacity, null);

  void add(VpnLogEntry entry) {
    _buffer[_head] = entry;
    _head = (_head + 1) % _buffer.length;
    if (_count < _buffer.length) _count++;
  }

  List<VpnLogEntry> toList() {
    if (_count < _buffer.length) {
      return _buffer.whereType<VpnLogEntry>().toList();
    }
    return List.generate(_buffer.length, (i) => _buffer[(_head + i) % _buffer.length]!);
  }
}

class LogService extends Notifier<List<VpnLogEntry>> {
  late final _CircularBuffer _buffer;

  @override
  List<VpnLogEntry> build() {
    _buffer = _CircularBuffer(AppConstants.maxLogEntries);
    return [];
  }

  void add(VpnLogEntry entry) {
    _buffer.add(entry);
    state = _buffer.toList();
  }

  void addInfo(String message, {String? source}) =>
      add(VpnLogEntry.info(message, source: source));

  void addError(String message, {String? source}) =>
      add(VpnLogEntry.error(message, source: source));

  void addWarning(String message, {String? source}) =>
      add(VpnLogEntry.warning(message, source: source));

  void addDebug(String message, {String? source}) =>
      add(VpnLogEntry.debug(message, source: source));

  void clear() {
    _buffer = _CircularBuffer(AppConstants.maxLogEntries);
    state = [];
  }
}

final logServiceProvider =
    NotifierProvider<LogService, List<VpnLogEntry>>(LogService.new);