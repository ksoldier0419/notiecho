import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/word_entry.dart';
import '../services/word_store.dart';
import '../services/audio_service.dart';
import '../theme.dart';

/// 시험 탭: 능동적 회상(Active Recall) → 장기기억 승격
/// 모드 A: 발음 듣고 뜻 떠올리기
/// 모드 B: 뜻 보고 단어 말하기
class TestScreen extends StatefulWidget {
  const TestScreen({super.key});

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  static const int promotionStreak = 3; // 연속 3회 정답 → 장기기억 승격

  String _mode = 'listen'; // listen: 발음→뜻 | meaning: 뜻→단어
  String? _selectedTag;
  bool _testStarted = false;
  bool _revealed = false;

  List<WordEntry> _queue = [];
  int _currentIndex = 0;
  int _sessionCorrect = 0;
  int _sessionWrong = 0;
  final List<String> _promotedWords = [];

  void _startTest(WordStore store) {
    final words = store.filter(tag: _selectedTag, stage: 'short');
    if (words.isEmpty) return;
    words.shuffle();
    setState(() {
      _queue = words;
      _currentIndex = 0;
      _sessionCorrect = 0;
      _sessionWrong = 0;
      _promotedWords.clear();
      _testStarted = true;
      _revealed = false;
    });
    if (_mode == 'listen') {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted && _queue.isNotEmpty) {
          AudioService().pronounce(_queue[0].word, audioUrl: _queue[0].nativeAudioUrl);
        }
      });
    }
  }

  WordEntry? get _current =>
      (_testStarted && _currentIndex < _queue.length) ? _queue[_currentIndex] : null;

  Future<void> _answer(bool correct) async {
    final w = _current;
    if (w == null) return;
    final store = context.read<WordStore>();

    if (correct) {
      w.correctStreak += 1;
      w.testCorrect += 1;
      _sessionCorrect++;
      if (w.correctStreak >= promotionStreak) {
        w.stage = 'long';
        _promotedWords.add(w.word);
      }
    } else {
      w.correctStreak = 0;
      w.testWrong += 1;
      _sessionWrong++;
    }
    await store.updateWord(w);

    if (!mounted) return;
    if (_currentIndex + 1 >= _queue.length) {
      // 세션 종료
      setState(() {
        _testStarted = false;
      });
      _showResultDialog();
    } else {
      setState(() {
        _currentIndex++;
        _revealed = false;
      });
      if (_mode == 'listen') {
        AudioService().pronounce(_queue[_currentIndex].word, audioUrl: _queue[_currentIndex].nativeAudioUrl);
      }
    }
  }

  void _showResultDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.emoji_events, color: Colors.amber),
            SizedBox(width: 8),
            Text('시험 완료!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('✅ 맞음: $_sessionCorrect개'),
            Text('❌ 틀림: $_sessionWrong개'),
            const SizedBox(height: 12),
            if (_promotedWords.isNotEmpty) ...[
              const Text('🎓 장기기억 창고로 승격:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(_promotedWords.join(', '),
                  style: const TextStyle(color: AppTheme.teal)),
            ] else
              Text(
                '연속 $promotionStreak회 정답을 맞히면\n장기기억 창고로 승격됩니다!',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<WordStore>();
    return Scaffold(
      appBar: AppBar(title: const Text('시험 · 장기기억 승격')),
      body: _testStarted ? _buildTestView(store) : _buildSetupView(store),
    );
  }

  // ─── 시험 설정 화면 ───
  Widget _buildSetupView(WordStore store) {
    final shortWords = store.filter(tag: _selectedTag, stage: 'short');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: AppTheme.deepIndigo,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.psychology, color: Colors.white, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '스스로 떠올리는 것(능동적 회상)이 가장 강력한 암기법!\n연속 $promotionStreak회 정답 → 장기기억 창고 🎓',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text('시험 방식',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          _modeCard(
            value: 'listen',
            icon: Icons.hearing,
            title: '발음 듣고 뜻 말하기',
            subtitle: 'AI 발음을 듣고 → 뜻을 소리 내어 말한 뒤 확인',
          ),
          const SizedBox(height: 8),
          _modeCard(
            value: 'meaning',
            icon: Icons.translate,
            title: '뜻 보고 단어 말하기',
            subtitle: '뜻을 보고 → 단어를 소리 내어 말한 뒤 확인',
          ),
          const SizedBox(height: 20),
          const Text('태그 범위',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('전체'),
                selected: _selectedTag == null,
                onSelected: (_) => setState(() => _selectedTag = null),
              ),
              ...store.tags.map((t) => ChoiceChip(
                    label: Text(t),
                    selected: _selectedTag == t,
                    selectedColor: AppTheme.lightTeal,
                    onSelected: (_) => setState(
                        () => _selectedTag = _selectedTag == t ? null : t),
                  )),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed:
                  shortWords.isEmpty ? null : () => _startTest(store),
              icon: const Icon(Icons.play_arrow),
              label: Text(
                shortWords.isEmpty
                    ? '시험 볼 단기기억 단어가 없어요'
                    : '시험 시작 (${shortWords.length}개 단어)',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (store.longTermCount > 0)
            Center(
              child: Text(
                '🏆 장기기억 창고에 ${store.longTermCount}개 단어 보관 중',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  Widget _modeCard({
    required String value,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _mode == value;
    return Card(
      color: selected ? AppTheme.lightTeal.withValues(alpha: 0.4) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? AppTheme.teal : Colors.transparent,
          width: 2,
        ),
      ),
      child: ListTile(
        leading: Icon(icon,
            color: selected ? AppTheme.deepIndigo : Colors.grey, size: 28),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: selected
            ? const Icon(Icons.check_circle, color: AppTheme.teal)
            : null,
        onTap: () => setState(() => _mode = value),
      ),
    );
  }

  // ─── 시험 진행 화면 ───
  Widget _buildTestView(WordStore store) {
    final w = _current;
    if (w == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // 진행률
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: (_currentIndex + 1) / _queue.length,
                  backgroundColor: Colors.grey.shade200,
                  color: AppTheme.teal,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Text('${_currentIndex + 1} / ${_queue.length}'),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: '시험 중단',
                onPressed: () => setState(() => _testStarted = false),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // 문제 카드
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_mode == 'listen') ...[
                      const Text('발음을 듣고 뜻을 소리 내어 말해보세요',
                          style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 20),
                      IconButton(
                        iconSize: 72,
                        icon: const Icon(Icons.volume_up_rounded,
                            color: AppTheme.deepIndigo),
                        onPressed: () => AudioService().pronounce(w.word, audioUrl: w.nativeAudioUrl),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => AudioService().pronounce(w.word, audioUrl: w.nativeAudioUrl),
                        icon: const Icon(Icons.replay, size: 16),
                        label: const Text('다시 듣기'),
                      ),
                    ] else ...[
                      const Text('이 뜻의 단어를 소리 내어 말해보세요',
                          style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 20),
                      Text(
                        w.meaning.isEmpty ? '(뜻 없음 — 단어를 떠올려보세요)' : w.meaning,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w600),
                      ),
                    ],
                    const SizedBox(height: 28),
                    // 정답 공개 영역
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _revealed
                          ? Column(
                              key: const ValueKey('answer'),
                              children: [
                                const Divider(),
                                const SizedBox(height: 12),
                                Text(
                                  w.word,
                                  style: const TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.deepIndigo),
                                ),
                                if (_mode == 'meaning')
                                  IconButton(
                                    icon: const Icon(Icons.volume_up,
                                        color: AppTheme.teal),
                                    onPressed: () =>
                                        AudioService().pronounce(w.word, audioUrl: w.nativeAudioUrl),
                                  ),
                                if (_mode == 'listen' && w.meaning.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      w.meaning,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 15),
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                Text(
                                  '연속 정답: ${w.correctStreak} / $promotionStreak',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600),
                                ),
                              ],
                            )
                          : FilledButton.tonal(
                              key: const ValueKey('reveal'),
                              onPressed: () =>
                                  setState(() => _revealed = true),
                              child: const Text('정답 확인'),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 정답/오답 버튼
          if (_revealed)
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade400,
                        padding: const EdgeInsets.symmetric(vertical: 16)),
                    onPressed: () => _answer(false),
                    icon: const Icon(Icons.close),
                    label: const Text('몰랐어요',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.teal,
                        padding: const EdgeInsets.symmetric(vertical: 16)),
                    onPressed: () => _answer(true),
                    icon: const Icon(Icons.check),
                    label: const Text('말했어요!',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
