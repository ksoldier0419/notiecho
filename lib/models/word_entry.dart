/// 기억 단계 정의
/// short3 → short5 → short10 → short15 → long30 → long60 → long120
class MemoryStage {
  static const List<String> all = [
    'short3', 'short5', 'short10', 'short15', 'long30', 'long60', 'long120',
  ];

  // 단계 → 복습 주기(일)
  static const Map<String, int> days = {
    'short3':   3,
    'short5':   5,
    'short10':  10,
    'short15':  15,
    'long30':   30,
    'long60':   60,
    'long120':  120,
  };

  // 단계 → 표시 라벨
  static const Map<String, String> label = {
    'short3':   '단기3',
    'short5':   '단기5',
    'short10':  '단기10',
    'short15':  '단기15',
    'long30':   '장기30',
    'long60':   '장기60',
    'long120':  '장기120',
  };

  // 시험 가중치 (장기60/120은 0 → 시험 제외)
  static const Map<String, int> weight = {
    'short3':   5,
    'short5':   4,
    'short10':  3,
    'short15':  2,
    'long30':   1,
    'long60':   0,
    'long120':  0,
  };

  static bool isLong(String stage) => stage.startsWith('long');
  static bool isShort(String stage) => stage.startsWith('short');

  /// 한 단계 승급 (마지막 단계면 유지)
  static String promote(String stage) {
    final i = all.indexOf(stage);
    if (i < 0 || i >= all.length - 1) return stage;
    return all[i + 1];
  }

  /// 한 단계 강등 (첫 단계면 short3 유지)
  static String demote(String stage) {
    final i = all.indexOf(stage);
    if (i <= 0) return 'short3';
    return all[i - 1];
  }

  /// 기존 2단계 → 7단계 마이그레이션
  static String migrate(String old) {
    if (all.contains(old)) return old; // 이미 새 형식
    if (old == 'long') return 'long30';
    return 'short3'; // 'short' 또는 기타 모두
  }

  /// 유효한 단계인지 확인
  static bool isValid(String stage) => all.contains(stage);

  static int getDays(String stage) => days[stage] ?? 3;
  static String getLabel(String stage) => label[stage] ?? stage;
  static int getWeight(String stage) => weight[stage] ?? 0;
}

/// 단어 데이터 모델
class WordEntry {
  final String id;
  String word;
  String meaning;
  List<String> tags;
  DateTime stageDate;   // 현재 단계에 진입한 날짜 (복습 주기 기준)
  final DateTime createdAt; // 최초 등록일 (변경 안됨)
  String? myVoicePath;
  String? nativeAudioUrl;
  String stage; // MemoryStage.all 중 하나
  int playCount;
  int testCorrect;
  int testWrong;

  WordEntry({
    required this.id,
    required this.word,
    this.meaning = '',
    List<String>? tags,
    DateTime? stageDate,
    DateTime? createdAt,
    this.myVoicePath,
    this.nativeAudioUrl,
    String? stage,
    this.playCount = 0,
    this.testCorrect = 0,
    this.testWrong = 0,
  })  : tags = tags ?? [],
        stage = MemoryStage.migrate(stage ?? 'short3'),
        stageDate = stageDate ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  bool get isLongTerm => MemoryStage.isLong(stage);
  bool get isShortTerm => MemoryStage.isShort(stage);
  String get stageLabel => MemoryStage.getLabel(stage);
  int get stageDays => MemoryStage.getDays(stage);

  /// 단계 진입 후 경과 일수
  int get daysInStage {
    final now = DateTime.now();
    return now.difference(DateTime(stageDate.year, stageDate.month, stageDate.day)).inDays;
  }

  /// 복습 주기 초과 여부
  bool get isOverdue => daysInStage > stageDays;

  Map<String, dynamic> toMap() => {
        'id': id,
        'word': word,
        'meaning': meaning,
        'tags': tags,
        'stageDate': stageDate.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'myVoicePath': myVoicePath,
        'nativeAudioUrl': nativeAudioUrl,
        'stage': stage,
        'playCount': playCount,
        'testCorrect': testCorrect,
        'testWrong': testWrong,
      };

  factory WordEntry.fromMap(Map<dynamic, dynamic> map) {
    final rawStage = (map['stage'] as String?) ?? 'short3';
    final migratedStage = MemoryStage.migrate(rawStage);

    // stageDate: 신규 필드. 없으면 기존 createdAt 사용
    final createdAtStr = (map['createdAt'] as String?) ?? '';
    final createdAt = DateTime.tryParse(createdAtStr) ?? DateTime.now();
    final stageDateStr = (map['stageDate'] as String?) ?? '';
    final stageDate = DateTime.tryParse(stageDateStr) ?? createdAt;

    return WordEntry(
      id: (map['id'] as String?) ?? DateTime.now().millisecondsSinceEpoch.toString(),
      word: (map['word'] as String?) ?? '',
      meaning: (map['meaning'] as String?) ?? '',
      tags: (map['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
      stageDate: stageDate,
      createdAt: createdAt,
      myVoicePath: map['myVoicePath'] as String?,
      nativeAudioUrl: map['nativeAudioUrl'] as String?,
      stage: migratedStage,
      playCount: (map['playCount'] as num?)?.toInt() ?? 0,
      testCorrect: (map['testCorrect'] as num?)?.toInt() ?? 0,
      testWrong: (map['testWrong'] as num?)?.toInt() ?? 0,
    );
  }
}
