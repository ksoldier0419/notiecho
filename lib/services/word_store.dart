import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/word_entry.dart';

/// 단어/태그 저장소 (Hive 기반) + 상태관리
class WordStore extends ChangeNotifier {
  static const String wordsBoxName = 'words_box';
  static const String tagsBoxName = 'tags_box';

  late Box _wordsBox;
  late Box _tagsBox;

  List<WordEntry> _words = [];
  List<String> _tags = [];

  List<WordEntry> get words => List.unmodifiable(_words);
  List<String> get tags => List.unmodifiable(_tags);

  Future<void> init() async {
    await Hive.initFlutter();
    _wordsBox = await Hive.openBox(wordsBoxName);
    _tagsBox = await Hive.openBox(tagsBoxName);
    _loadAll();
  }

  void _loadAll() {
    _words = _wordsBox.values
        .map((e) => WordEntry.fromMap(Map<dynamic, dynamic>.from(e as Map)))
        .toList();
    // 최신순 정렬
    _words.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _tags = _tagsBox.values.map((e) => e.toString()).toList();
    notifyListeners();
  }

  // ─── Words ───
  Future<void> addWord(WordEntry entry) async {
    await _wordsBox.put(entry.id, entry.toMap());
    _words.insert(0, entry);
    notifyListeners();
  }

  Future<void> updateWord(WordEntry entry) async {
    await _wordsBox.put(entry.id, entry.toMap());
    final idx = _words.indexWhere((w) => w.id == entry.id);
    if (idx >= 0) _words[idx] = entry;
    notifyListeners();
  }

  Future<void> deleteWord(String id) async {
    await _wordsBox.delete(id);
    _words.removeWhere((w) => w.id == id);
    notifyListeners();
  }

  // ─── Tags ───
  Future<void> addTag(String tag) async {
    final t = tag.trim();
    if (t.isEmpty || _tags.contains(t)) return;
    await _tagsBox.add(t);
    _tags.add(t);
    notifyListeners();
  }

  Future<void> renameTag(String oldTag, String newTag) async {
    final t = newTag.trim();
    if (t.isEmpty || oldTag == t || _tags.contains(t)) return;
    // 태그 박스 갱신
    final keys = _tagsBox.keys.toList();
    for (final k in keys) {
      if (_tagsBox.get(k).toString() == oldTag) {
        await _tagsBox.put(k, t);
      }
    }
    // 단어들의 태그 갱신 (새 List로 교체해서 unmodifiable 방지)
    for (final w in _words) {
      if (w.tags.contains(oldTag)) {
        w.tags = w.tags.map((tag) => tag == oldTag ? t : tag).toList();
        await _wordsBox.put(w.id, w.toMap());
      }
    }
    final idx = _tags.indexOf(oldTag);
    if (idx >= 0) _tags[idx] = t;
    notifyListeners();
  }

  Future<void> deleteTag(String tag) async {
    final keys = _tagsBox.keys.toList();
    for (final k in keys) {
      if (_tagsBox.get(k).toString() == tag) {
        await _tagsBox.delete(k);
      }
    }
    for (final w in _words) {
      if (w.tags.contains(tag)) {
        w.tags = w.tags.where((t) => t != tag).toList();
        await _wordsBox.put(w.id, w.toMap());
      }
    }
    _tags.remove(tag);
    notifyListeners();
  }

  // ─── 필터 ───
  List<WordEntry> filter({
    String? tag,
    DateTime? date,
    String? stage,
  }) {
    return _words.where((w) {
      if (tag != null && !w.tags.contains(tag)) return false;
      if (date != null) {
        final d = w.createdAt;
        if (d.year != date.year || d.month != date.month || d.day != date.day) {
          return false;
        }
      }
      if (stage != null && w.stage != stage) return false;
      return true;
    }).toList();
  }

  // ─── 통계 ───
  int get totalCount => _words.length;
  int get shortTermCount => _words.where((w) => w.stage == 'short').length;
  int get longTermCount => _words.where((w) => w.stage == 'long').length;
  int get todayCount {
    final now = DateTime.now();
    return _words
        .where((w) =>
            w.createdAt.year == now.year &&
            w.createdAt.month == now.month &&
            w.createdAt.day == now.day)
        .length;
  }
}
