import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class HistoryEntry {
  final String text;
  final DateTime timestamp;
  HistoryEntry(this.text, this.timestamp);

  Map<String, dynamic> toJson() => {
    'text': text,
    'timestamp': timestamp.toIso8601String(),
  };

  static HistoryEntry fromJson(Map<String, dynamic> json) => HistoryEntry(
    json['text'] as String,
    DateTime.parse(json['timestamp'] as String),
  );
}

class HistoryService {
  static const _key = 'text_reader_history';

  final SharedPreferences _prefs;
  HistoryService(this._prefs);

  Future<List<HistoryEntry>> getHistory() async {
    final raw = _prefs.getStringList(_key) ?? [];
    return raw.map((s) {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return HistoryEntry.fromJson(m);
    }).toList();
  }

  Future<void> addEntry(String text) async {
    final hist = await getHistory();
    hist.insert(0, HistoryEntry(text, DateTime.now()));
    final encoded = hist.map((e) => jsonEncode(e.toJson())).toList();
    await _prefs.setStringList(_key, encoded);
  }

  Future<void> clear() async => _prefs.remove(_key);
}
