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
    // 앱 시작 시 stage 마이그레이션 (old: 'short'/'long' → new 7단계)
    await _migrateStages();
  }

  void _loadAll() {
    _words = _wordsBox.values
        .map((e) => WordEntry.fromMap(Map<dynamic, dynamic>.from(e as Map)))
        .toList();
    _words.sort((a, b) => b.stageDate.compareTo(a.stageDate));
    _tags = _tagsBox.values.map((e) => e.toString()).toList();
    notifyListeners();
  }

  /// 기존 'short'/'long' 2단계 → 7단계 자동 마이그레이션
  Future<void> _migrateStages() async {
    bool changed = false;
    for (final w in _words) {
      final migrated = MemoryStage.migrate(w.stage);
      if (migrated != w.stage) {
        w.stage = migrated;
        await _wordsBox.put(w.id, w.toMap());
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  // ─── Words ───────────────────────────────────────────────

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

  // ─── 단계 승급 (시험 통과) ───────────────────────────────
  Future<void> promoteStage(WordEntry w) async {
    w.stage = MemoryStage.promote(w.stage);
    w.stageDate = DateTime.now();
    await updateWord(w);
  }

  // ─── 단계 강등 (시험 실패 / 모르겠어요) ─────────────────
  Future<void> demoteStage(WordEntry w) async {
    w.stage = MemoryStage.demote(w.stage);
    w.stageDate = DateTime.now();
    await updateWord(w);
  }

  // ─── 단계 일괄 수정 (관리 탭 버튼) ──────────────────────
  /// 복습 주기 초과한 단어를 한 단계 강등 + stageDate 오늘로 갱신
  /// 반환값: 변경된 단어 수
  Future<int> reviewAndDemoteOverdue() async {
    int count = 0;
    final today = DateTime.now();
    for (final w in _words) {
      final daysElapsed = today
          .difference(
            DateTime(w.stageDate.year, w.stageDate.month, w.stageDate.day),
          )
          .inDays;
      final n = MemoryStage.getDays(w.stage);
      if (daysElapsed > n) {
        w.stage = MemoryStage.demote(w.stage);
        w.stageDate = today;
        await _wordsBox.put(w.id, w.toMap());
        count++;
      }
    }
    if (count > 0) {
      _words.sort((a, b) => b.stageDate.compareTo(a.stageDate));
      notifyListeners();
    }
    return count;
  }

  // ─── Tags ────────────────────────────────────────────────

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
    final keys = _tagsBox.keys.toList();
    for (final k in keys) {
      if (_tagsBox.get(k).toString() == oldTag) {
        await _tagsBox.put(k, t);
      }
    }
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

  // ─── 필터 ─────────────────────────────────────────────────

  List<WordEntry> filter({
    List<String>? tags,   // 여러 태그 OR 필터
    String? stage,        // 특정 단계
    bool? isLong,         // 장기/단기 구분
  }) {
    return _words.where((w) {
      if (tags != null && tags.isNotEmpty) {
        if (!tags.any((t) => w.tags.contains(t))) return false;
      }
      if (stage != null && w.stage != stage) return false;
      if (isLong != null && MemoryStage.isLong(w.stage) != isLong) return false;
      return true;
    }).toList();
  }

  // ─── 통계 ─────────────────────────────────────────────────

  int get totalCount => _words.length;

  int get shortTermCount =>
      _words.where((w) => MemoryStage.isShort(w.stage)).length;

  int get longTermCount =>
      _words.where((w) => MemoryStage.isLong(w.stage)).length;

  int get todayCount {
    final now = DateTime.now();
    return _words
        .where((w) =>
            w.createdAt.year == now.year &&
            w.createdAt.month == now.month &&
            w.createdAt.day == now.day)
        .length;
  }

  /// 단계별 단어 수 Map
  Map<String, int> get stageCounts {
    final m = <String, int>{};
    for (final s in MemoryStage.all) {
      m[s] = _words.where((w) => w.stage == s).length;
    }
    return m;
  }

  /// 시험 대상 단어 (가중치 > 0인 단계만) — 태그 필터 가능
  List<WordEntry> examCandidates({List<String>? tags}) {
    return _words.where((w) {
      if (MemoryStage.getWeight(w.stage) == 0) return false;
      if (tags != null && tags.isNotEmpty) {
        if (!tags.any((t) => w.tags.contains(t))) return false;
      }
      return true;
    }).toList();
  }
}
