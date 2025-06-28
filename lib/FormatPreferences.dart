import 'package:flutter/foundation.dart';

class FormatPreferences extends ChangeNotifier {
  String _dateFormat = 'yyyy/mm/dd';
  String _timeFormat = '24h';
  String _fileNamingPrefix = 'yyyy_mm_dd_hh_mm_ss';
  bool _formatEnabled = false;

  String get dateFormat => _dateFormat;
  String get timeFormat => _timeFormat;
  String get fileNamingPrefix => _fileNamingPrefix;
  bool get formatEnabled => _formatEnabled;

  void updateDateFormat(String format) {
    _dateFormat = format;
    _updateFileNamingPrefix();
    notifyListeners();
  }

  void updateTimeFormat(String format) {
    _timeFormat = format;
    _updateFileNamingPrefix();
    notifyListeners();
  }

  void updateFileNamingPrefix(String prefix) {
    _fileNamingPrefix = prefix;
    notifyListeners();
  }

  void setFormatEnabled(bool enabled) {
    _formatEnabled = enabled;
    notifyListeners();
  }

  void _updateFileNamingPrefix() {
    _fileNamingPrefix = '${_dateFormat.replaceAll('/', '_')}_${_timeFormat.replaceAll(':', '_')}';
  }
}