import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/word_entry.dart';
import '../services/word_store.dart';
import '../services/audio_service.dart';
import '../theme.dart';

/// 시험 탭
/// 1단계: 태그 선택 + 문항수 선택 → 시험 시작
/// 2단계: 뜻(한국어) TTS → [모르겠어요] [말했어요] → 정답 표시 → 단계 이동
class TestScreen extends StatefulWidget {
  const TestScreen({super.key});

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  // ── 시험 설정 ─────────────────────────────────────────────
  Set<String> _selectedTags = {};
  int? _targetCount; // null = 아직 미선택
  String _examMode = 'meaning'; // 'meaning' = 뜻→단어 | 'word' = 단어→뜻
  bool _examStarted = false;

  // ── 시험 진행 ─────────────────────────────────────────────
  List<WordEntry> _questions = [];
  int _currentIdx = 0;
  bool _answerRevealed = false;
  bool _ttsPlaying = false;

  // ── 통계 ─────────────────────────────────────────────────
  int _correctCount = 0;
  int _wrongCount = 0;
  bool _examFinished = false;
  List<Map<String, dynamic>> _results = []; // {word, correct}

  @override
  Widget build(BuildContext context) {
    final store = context.watch<WordStore>();
    if (_examFinished) return _buildResultScreen(store);
    if (_examStarted) return _buildExamScreen(store);
    return _buildSetupScreen(store);
  }

  // ══════════════════════════════════════════════════════════
  // 1단계: 시험 설정 화면
  // ══════════════════════════════════════════════════════════
  Widget _buildSetupScreen(WordStore store) {
    final candidates = store.examCandidates(
      tags: _selectedTags.isEmpty ? null : _selectedTags.toList(),
    );
    final total = candidates.length;
    final half = (total / 2).ceil();

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            // 안내
            Card(
              color: AppTheme.deepIndigo,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        color: Colors.white70, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '뜻(한국어)을 듣고 단어를 말하는 시험\n'
                        '시험 범위: 단기3~15 + 장기30 (장기60·120 제외)',
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 태그 선택
            _buildLabel(Icons.label, '태그 선택 (복수 선택 가능)'),
            const SizedBox(height: 8),
            if (store.tags.isEmpty)
              Text('태그가 없습니다. 전체 단어로 시험합니다.',
                  style: TextStyle(
                      color: Colors.grey.shade500, fontSize: 12))
            else
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  FilterChip(
                    label: const Text('전체'),
                    selected: _selectedTags.isEmpty,
                    selectedColor: AppTheme.lightTeal,
                    onSelected: (_) =>
                        setState(() => _selectedTags = {}),
                  ),
                  ...store.tags.map((tag) {
                    final cnt = store
                        .examCandidates(tags: [tag])
                        .length;
                    return FilterChip(
                      label: Text('$tag ($cnt)'),
                      selected: _selectedTags.contains(tag),
                      selectedColor: AppTheme.lightTeal,
                      checkmarkColor: AppTheme.deepIndigo,
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            _selectedTags = {..._selectedTags, tag};
                          } else {
                            _selectedTags = _selectedTags
                                .where((t) => t != tag)
                                .toSet();
                          }
                          _targetCount = null;
                        });
                      },
                    );
                  }),
                ],
              ),
            const SizedBox(height: 20),

            // 문항 수 선택
            _buildLabel(Icons.quiz, '문항 수 선택'),
            const SizedBox(height: 8),
            if (total == 0)
              Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.orange.shade700),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '시험 대상 단어가 없습니다.\n단어를 추가하거나 태그 선택을 변경해 보세요.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: _countButton(
                      label: '50%',
                      sub: '$half문제',
                      selected: _targetCount == half,
                      onTap: () =>
                          setState(() => _targetCount = half),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _countButton(
                      label: '100%',
                      sub: '$total문제',
                      selected: _targetCount == total,
                      onTap: () =>
                          setState(() => _targetCount = total),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            if (total > 0)
              _buildStageBreakdown(store, candidates),
            const SizedBox(height: 24),

            // 시작 버튼
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (total > 0 && _targetCount != null)
                    ? () => _startExam(store)
                    : null,
                icon: const Icon(Icons.play_arrow_rounded, size: 22),
                label: Text(
                  _targetCount == null
                      ? '문항 수를 선택하세요'
                      : '시험 시작 ($_targetCount문제)',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: AppTheme.indigo,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.deepIndigo),
        const SizedBox(width: 6),
        Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  Widget _countButton({
    required String label,
    required String sub,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: selected ? AppTheme.lightTeal : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? AppTheme.teal : Colors.grey.shade300,
              width: selected ? 2 : 1),
        ),
        child: Column(
          children: [
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: selected
                        ? AppTheme.deepIndigo
                        : Colors.grey.shade700)),
            Text(sub,
                style: TextStyle(
                    fontSize: 12,
                    color: selected
                        ? AppTheme.teal
                        : Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }

  /// 단계별 문항 구성 미리보기
  Widget _buildStageBreakdown(WordStore store, List<WordEntry> candidates) {
    final stageCnt = <String, int>{};
    for (final w in candidates) {
      stageCnt[w.stage] = (stageCnt[w.stage] ?? 0) + 1;
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('시험 대상 구성',
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: MemoryStage.all
                .where((s) => MemoryStage.getWeight(s) > 0)
                .map((s) {
              final cnt = stageCnt[s] ?? 0;
              final w = MemoryStage.getWeight(s);
              return Chip(
                label: Text(
                    '${MemoryStage.getLabel(s)}: $cnt개 (×$w)',
                    style: const TextStyle(fontSize: 11)),
                backgroundColor:
                    Colors.grey.shade100,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // 시험 시작: 가중치 랜덤 문항 구성
  // ══════════════════════════════════════════════════════════
  void _startExam(WordStore store) {
    final candidates = store.examCandidates(
      tags: _selectedTags.isEmpty ? null : _selectedTags.toList(),
    );
    if (candidates.isEmpty) return;

    // 가중치 적용 풀 생성
    final pool = <WordEntry>[];
    for (final w in candidates) {
      final wt = MemoryStage.getWeight(w.stage);
      for (int i = 0; i < wt; i++) {
        pool.add(w);
      }
    }
    pool.shuffle(Random());

    // 중복 제거하면서 targetCount만큼 추출
    final seen = <String>{};
    final questions = <WordEntry>[];
    for (final w in pool) {
      if (!seen.contains(w.id)) {
        seen.add(w.id);
        questions.add(w);
        if (questions.length >= _targetCount!) break;
      }
    }
    // 부족하면 나머지 채우기
    if (questions.length < _targetCount!) {
      for (final w in candidates) {
        if (!seen.contains(w.id)) {
          seen.add(w.id);
          questions.add(w);
          if (questions.length >= _targetCount!) break;
        }
      }
    }

    setState(() {
      _questions = questions;
      _currentIdx = 0;
      _answerRevealed = false;
      _correctCount = 0;
      _wrongCount = 0;
      _results = [];
      _examStarted = true;
      _examFinished = false;
    });

    // 첫 문제 TTS 재생
    _playCurrentMeaning();
  }

  // ══════════════════════════════════════════════════════════
  // 2단계: 시험 진행 화면
  // ══════════════════════════════════════════════════════════
  Widget _buildExamScreen(WordStore store) {
    if (_questions.isEmpty) return const SizedBox.shrink();
    final q = _questions[_currentIdx];
    final progress = (_currentIdx + 1) / _questions.length;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 진행 바
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${_currentIdx + 1} / ${_questions.length}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          Icon(Icons.check_circle,
                              color: Colors.green.shade600, size: 16),
                          Text(' $_correctCount  ',
                              style: const TextStyle(fontSize: 13)),
                          Icon(Icons.cancel,
                              color: Colors.red.shade400, size: 16),
                          Text(' $_wrongCount',
                              style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: Colors.grey.shade200,
                      valueColor:
                          const AlwaysStoppedAnimation(AppTheme.teal),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const SizedBox(height: 16),

                    // 단계 뱃지
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.lightTeal.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        q.stageLabel,
                        style: const TextStyle(
                            color: AppTheme.deepIndigo,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 뜻 카드
                    Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Text(
                              '뜻 (한국어)',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              q.meaning.isNotEmpty
                                  ? q.meaning.split('\n').first
                                  : '(뜻 없음)',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  height: 1.4),
                            ),
                            const SizedBox(height: 16),
                            // TTS 재생 버튼
                            OutlinedButton.icon(
                              onPressed: _ttsPlaying
                                  ? null
                                  : _playCurrentMeaning,
                              icon: Icon(
                                _ttsPlaying
                                    ? Icons.volume_up
                                    : Icons.replay,
                                size: 18,
                              ),
                              label: Text(_ttsPlaying
                                  ? '재생 중...'
                                  : '다시 듣기'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.deepIndigo,
                                side: const BorderSide(
                                    color: AppTheme.teal),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    if (!_answerRevealed) ...[
                      // ── 정답 전: [모르겠어요] [말했어요] ──
                      Row(
                        children: [
                          // 모르겠어요 (좌)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  _onDontKnow(store, q),
                              style: OutlinedButton.styleFrom(
                                foregroundColor:
                                    Colors.grey.shade700,
                                side: BorderSide(
                                    color: Colors.grey.shade400),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(12)),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.help_outline,
                                      size: 24,
                                      color: Colors.grey.shade600),
                                  const SizedBox(height: 4),
                                  const Text('모르겠어요',
                                      style: TextStyle(
                                          fontWeight:
                                              FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // 말했어요 (우)
                          Expanded(
                            child: FilledButton(
                              onPressed: () =>
                                  _onSaidIt(q),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.indigo,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(12)),
                              ),
                              child: Column(
                                children: const [
                                  Icon(Icons.record_voice_over,
                                      size: 24),
                                  SizedBox(height: 4),
                                  Text('말했어요',
                                      style: TextStyle(
                                          fontWeight:
                                              FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      // ── 정답 공개 ──
                      _buildAnswerReveal(store, q),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 정답 공개 카드 (말했어요 선택 후)
  Widget _buildAnswerReveal(WordStore store, WordEntry q) {
    return Column(
      children: [
        Card(
          color: AppTheme.lightTeal.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text('정답',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 10),
                if (_examMode == 'meaning') ...[
                  // 뜻→단어 모드: 정답은 영어 단어
                  Text(
                    q.word,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.deepIndigo),
                  ),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: () => AudioService()
                        .pronounce(q.word, audioUrl: q.nativeAudioUrl),
                    icon: const Icon(Icons.volume_up, size: 18),
                    label: const Text('원어민 발음 듣기'),
                    style: TextButton.styleFrom(
                        foregroundColor: AppTheme.teal),
                  ),
                ] else ...[
                  // 단어→뜻 모드: 정답은 한국어 뜻
                  Text(
                    q.meaning.isNotEmpty
                        ? q.meaning.split('\n').first
                        : '(뜻 없음)',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        height: 1.4),
                  ),
                  const SizedBox(height: 4),
                  // 단어→뜻 모드에서도 영어 발음 한 번 더 들을 수 있게
                  TextButton.icon(
                    onPressed: () => AudioService()
                        .pronounce(q.word, audioUrl: q.nativeAudioUrl),
                    icon: const Icon(Icons.volume_up, size: 18),
                    label: Text('${q.word} 발음 듣기'),
                    style: TextButton.styleFrom(
                        foregroundColor: AppTheme.teal),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // 맞아요 / 틀렸네요
        Row(
          children: [
            // 틀렸네요 (좌)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _onWrong(store, q),
                icon: const Icon(Icons.close, size: 20),
                label: const Text('틀렸네요',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade600,
                  side: BorderSide(color: Colors.red.shade300),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 맞아요 (우)
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _onCorrect(store, q),
                icon: const Icon(Icons.check, size: 20),
                label: const Text('맞아요',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════
  // 시험 액션
  // ══════════════════════════════════════════════════════════

  Future<void> _playCurrentMeaning() async {
    if (_questions.isEmpty) return;
    final q = _questions[_currentIdx];
    if (q.meaning.isEmpty) return;
    setState(() => _ttsPlaying = true);
    try {
      await AudioService().speakKorean(q.meaning.split('\n').first);
    } finally {
      if (mounted) setState(() => _ttsPlaying = false);
    }
  }

  /// 말했어요 → 정답 공개
  void _onSaidIt(WordEntry q) {
    setState(() => _answerRevealed = true);
  }

  /// 모르겠어요 → 정답 공개 + 강등 + 다음 문제
  Future<void> _onDontKnow(WordStore store, WordEntry q) async {
    setState(() => _answerRevealed = true);
    _results.add({'word': q.word, 'correct': false});
    _wrongCount++;
    await store.demoteStage(q);
    // 잠깐 정답 보여준 후 다음으로
    await Future.delayed(const Duration(milliseconds: 1200));
    _nextQuestion();
  }

  /// 맞아요 → 승급 + 다음 문제
  Future<void> _onCorrect(WordStore store, WordEntry q) async {
    _results.add({'word': q.word, 'correct': true});
    _correctCount++;
    await store.promoteStage(q);
    _nextQuestion();
  }

  /// 틀렸네요 → 강등 + 다음 문제
  Future<void> _onWrong(WordStore store, WordEntry q) async {
    _results.add({'word': q.word, 'correct': false});
    _wrongCount++;
    await store.demoteStage(q);
    _nextQuestion();
  }

  void _nextQuestion() {
    if (_currentIdx + 1 >= _questions.length) {
      setState(() => _examFinished = true);
      return;
    }
    setState(() {
      _currentIdx++;
      _answerRevealed = false;
    });
    _playCurrentMeaning();
  }

  // ══════════════════════════════════════════════════════════
  // 3단계: 결과 화면
  // ══════════════════════════════════════════════════════════
  Widget _buildResultScreen(WordStore store) {
    final total = _results.length;
    final correct = _correctCount;
    final rate = total > 0 ? (correct / total * 100).round() : 0;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 16),
              // 점수 카드
              Card(
                color: AppTheme.deepIndigo,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Text('시험 완료!',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 14)),
                      const SizedBox(height: 12),
                      Text('$rate%',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 52,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('$total문제 중 $correct개 정답',
                          style: const TextStyle(
                              color: Colors.white70)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 틀린 단어 목록
              if (_results.any((r) => !(r['correct'] as bool))) ...[
                _buildSectionLabel('❌ 틀린 단어'),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: _results
                        .where((r) => !(r['correct'] as bool))
                        .map((r) => ListTile(
                              dense: true,
                              leading: const Icon(Icons.close,
                                  color: Colors.red, size: 18),
                              title: Text(r['word'] as String,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // 맞은 단어 목록
              if (_results.any((r) => r['correct'] as bool)) ...[
                _buildSectionLabel('✅ 맞은 단어'),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: _results
                        .where((r) => r['correct'] as bool)
                        .map((r) => ListTile(
                              dense: true,
                              leading: const Icon(Icons.check_circle,
                                  color: Colors.green, size: 18),
                              title: Text(r['word'] as String,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // 다시 시험 / 설정으로
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() {
                        _examStarted = false;
                        _examFinished = false;
                        _targetCount = null;
                      }),
                      icon: const Icon(Icons.settings, size: 18),
                      label: const Text('설정으로'),
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _startExam(store),
                      icon: const Icon(Icons.replay, size: 18),
                      label: const Text('다시 시험'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.indigo,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(text,
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 14)),
    );
  }
}
