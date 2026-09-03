/// 단어 데이터 모델
class WordEntry {
  final String id;
  String word; // 정정된 오리지널 단어
  String meaning; // 뜻
  List<String> tags;
  final DateTime createdAt;
  String? myVoicePath; // 내 목소리 녹음 파일 경로 (or blob url on web)
  String stage; // 'short' (단기기억) | 'long' (장기기억)
  int correctStreak; // 연속 정답 횟수
  int playCount; // 재생 횟수
  int testCorrect;
  int testWrong;

  WordEntry({
    required this.id,
    required this.word,
    this.meaning = '',
    List<String>? tags,
    DateTime? createdAt,
    this.myVoicePath,
    this.stage = 'short',
    this.correctStreak = 0,
    this.playCount = 0,
    this.testCorrect = 0,
    this.testWrong = 0,
  })  : tags = tags ?? [],
        createdAt = createdAt ?? DateTime.now();

  bool get isLongTerm => stage == 'long';

  Map<String, dynamic> toMap() => {
        'id': id,
        'word': word,
        'meaning': meaning,
        'tags': tags,
        'createdAt': createdAt.toIso8601String(),
        'myVoicePath': myVoicePath,
        'stage': stage,
        'correctStreak': correctStreak,
        'playCount': playCount,
        'testCorrect': testCorrect,
        'testWrong': testWrong,
      };

  factory WordEntry.fromMap(Map<dynamic, dynamic> map) => WordEntry(
        id: (map['id'] as String?) ?? DateTime.now().millisecondsSinceEpoch.toString(),
        word: (map['word'] as String?) ?? '',
        meaning: (map['meaning'] as String?) ?? '',
        tags: (map['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
        createdAt: DateTime.tryParse((map['createdAt'] as String?) ?? '') ?? DateTime.now(),
        myVoicePath: map['myVoicePath'] as String?,
        stage: (map['stage'] as String?) ?? 'short',
        correctStreak: (map['correctStreak'] as num?)?.toInt() ?? 0,
        playCount: (map['playCount'] as num?)?.toInt() ?? 0,
        testCorrect: (map['testCorrect'] as num?)?.toInt() ?? 0,
        testWrong: (map['testWrong'] as num?)?.toInt() ?? 0,
      );
}
