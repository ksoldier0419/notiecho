import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/word_entry.dart';
import '../services/word_store.dart';
import '../services/audio_service.dart';
import '../theme.dart';

/// 플레이 탭: 태그/날짜 필터 → 리스트업 → 단일/반복 재생 (단기기억 강화)
class PlayScreen extends StatefulWidget {
  const PlayScreen({super.key});

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  String? _selectedTag;
  DateTime? _selectedDate;
  String _stageFilter = 'short'; // short | long | all

  final Set<String> _checkedIds = {};
  bool _isPlayingAll = false;
  bool _loopMode = true;
  int _repeatPerWord = 2; // 단어당 반복 횟수
  double _gapSeconds = 1.5; // 단어 사이 간격
  String _voiceMode = 'ai'; // ai | mine | both
  String? _currentPlayingId;
  int _cycleCount = 0;

  bool _stopRequested = false;

  List<WordEntry> _filteredWords(WordStore store) {
    return store.filter(
      tag: _selectedTag,
      date: _selectedDate,
      stage: _stageFilter == 'all' ? null : _stageFilter,
    );
  }

  List<WordEntry> _playlist(WordStore store) {
    final words = _filteredWords(store);
    if (_checkedIds.isEmpty) return words;
    return words.where((w) => _checkedIds.contains(w.id)).toList();
  }

  Future<void> _playSingle(WordEntry w) async {
    await _stopPlayback();
    setState(() => _currentPlayingId = w.id);
    await _playWord(w);
    if (mounted) setState(() => _currentPlayingId = null);
  }

  Future<void> _playWord(WordEntry w) async {
    final audio = AudioService();
    for (int i = 0; i < _repeatPerWord; i++) {
      if (_stopRequested) return;
      if (_voiceMode == 'mine' && w.myVoicePath != null) {
        await audio.playMyVoice(w.myVoicePath!);
      } else if (_voiceMode == 'both' && w.myVoicePath != null) {
        await audio.pronounce(w.word, audioUrl: w.nativeAudioUrl);
        if (_stopRequested) return;
        await Future.delayed(const Duration(milliseconds: 400));
        await audio.playMyVoice(w.myVoicePath!);
      } else {
        await audio.pronounce(w.word, audioUrl: w.nativeAudioUrl);
      }
      if (i < _repeatPerWord - 1 && !_stopRequested) {
        await Future.delayed(Duration(milliseconds: (_gapSeconds * 500).round()));
      }
    }
    // 재생 횟수 기록
    w.playCount += _repeatPerWord;
    if (mounted) {
      unawaited(context.read<WordStore>().updateWord(w));
    }
  }

  Future<void> _playAll(WordStore store) async {
    final list = _playlist(store);
    if (list.isEmpty) return;

    setState(() {
      _isPlayingAll = true;
      _stopRequested = false;
      _cycleCount = 0;
    });

    do {
      for (final w in list) {
        if (_stopRequested) break;
        if (mounted) setState(() => _currentPlayingId = w.id);
        await _playWord(w);
        if (_stopRequested) break;
        await Future.delayed(
            Duration(milliseconds: (_gapSeconds * 1000).round()));
      }
      if (!_stopRequested && mounted) {
        setState(() => _cycleCount++);
      }
    } while (_loopMode && !_stopRequested && mounted);

    if (mounted) {
      setState(() {
        _isPlayingAll = false;
        _currentPlayingId = null;
      });
    }
  }

  Future<void> _stopPlayback() async {
    _stopRequested = true;
    await AudioService().stopAll();
    if (mounted) {
      setState(() {
        _isPlayingAll = false;
        _currentPlayingId = null;
      });
    }
  }

  @override
  void dispose() {
    _stopRequested = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<WordStore>();
    final words = _filteredWords(store);

    return Scaffold(
      appBar: AppBar(title: const Text('플레이 · 반복 청취')),
      body: Column(
        children: [
          _buildFilterBar(store),
          _buildPlayControls(store, words),
          Expanded(
            child: words.isEmpty
                ? _buildEmpty()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: words.length,
                    itemBuilder: (context, i) => _buildWordTile(words[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(WordStore store) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // 기억단계 필터
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'short', label: Text('단기'), icon: Icon(Icons.hourglass_bottom, size: 14)),
                    ButtonSegment(value: 'long', label: Text('장기'), icon: Icon(Icons.emoji_events, size: 14)),
                    ButtonSegment(value: 'all', label: Text('전체')),
                  ],
                  selected: {_stageFilter},
                  onSelectionChanged: (s) =>
                      setState(() => _stageFilter = s.first),
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // 태그 필터
                ChoiceChip(
                  label: const Text('전체 태그'),
                  selected: _selectedTag == null,
                  onSelected: (_) => setState(() => _selectedTag = null),
                ),
                const SizedBox(width: 6),
                ...store.tags.map((t) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(t),
                        selected: _selectedTag == t,
                        selectedColor: AppTheme.lightTeal,
                        onSelected: (_) => setState(() =>
                            _selectedTag = _selectedTag == t ? null : t),
                      ),
                    )),
                const SizedBox(width: 6),
                // 날짜 필터
                ActionChip(
                  avatar: Icon(Icons.calendar_today,
                      size: 15,
                      color: _selectedDate != null
                          ? AppTheme.deepIndigo
                          : Colors.grey),
                  label: Text(_selectedDate == null
                      ? '날짜'
                      : DateFormat('M/d').format(_selectedDate!)),
                  backgroundColor: _selectedDate != null
                      ? AppTheme.lightTeal
                      : null,
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate ?? DateTime.now(),
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now(),
                    );
                    setState(() => _selectedDate = picked);
                  },
                ),
                if (_selectedDate != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _selectedDate = null),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayControls(WordStore store, List<WordEntry> words) {
    final playlistSize =
        _checkedIds.isEmpty ? words.length : _checkedIds.length;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            Row(
              children: [
                // 재생/정지 버튼
                FilledButton.icon(
                  onPressed: words.isEmpty
                      ? null
                      : () {
                          if (_isPlayingAll) {
                            _stopPlayback();
                          } else {
                            _playAll(store);
                          }
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        _isPlayingAll ? Colors.red.shade400 : AppTheme.teal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                  icon: Icon(_isPlayingAll
                      ? Icons.stop_rounded
                      : Icons.play_arrow_rounded),
                  label: Text(_isPlayingAll
                      ? '정지'
                      : (_loopMode ? '반복 재생' : '전체 재생')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _isPlayingAll
                        ? '재생 중 · ${_cycleCount + 1}회차 반복'
                        : '$playlistSize개 단어 대기 중',
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade700),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _loopMode ? Icons.repeat_on_rounded : Icons.repeat_rounded,
                    color: _loopMode ? AppTheme.teal : Colors.grey,
                  ),
                  tooltip: '리스트 무한 반복',
                  onPressed: () => setState(() => _loopMode = !_loopMode),
                ),
                IconButton(
                  icon: const Icon(Icons.tune),
                  tooltip: '재생 옵션',
                  onPressed: _showPlayOptions,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showPlayOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('재생 옵션',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Text('단어당 반복: $_repeatPerWord회'),
              Slider(
                value: _repeatPerWord.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                activeColor: AppTheme.teal,
                label: '$_repeatPerWord회',
                onChanged: (v) {
                  setSheet(() {});
                  setState(() => _repeatPerWord = v.round());
                },
              ),
              Text('단어 사이 간격: ${_gapSeconds.toStringAsFixed(1)}초 (따라 말하는 시간)'),
              Slider(
                value: _gapSeconds,
                min: 0.5,
                max: 5,
                divisions: 9,
                activeColor: AppTheme.teal,
                label: '${_gapSeconds.toStringAsFixed(1)}초',
                onChanged: (v) {
                  setSheet(() {});
                  setState(() => _gapSeconds = v);
                },
              ),
              const SizedBox(height: 8),
              const Text('목소리 선택'),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'ai', label: Text('AI 발음'), icon: Icon(Icons.smart_toy, size: 15)),
                  ButtonSegment(value: 'mine', label: Text('내 목소리'), icon: Icon(Icons.person, size: 15)),
                  ButtonSegment(value: 'both', label: Text('둘 다')),
                ],
                selected: {_voiceMode},
                onSelectionChanged: (s) {
                  setSheet(() {});
                  setState(() => _voiceMode = s.first);
                },
              ),
              const SizedBox(height: 8),
              Text(
                '※ 내 목소리 녹음이 없는 단어는 AI 발음으로 재생됩니다',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWordTile(WordEntry w) {
    final isChecked = _checkedIds.contains(w.id);
    final isPlaying = _currentPlayingId == w.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isPlaying ? AppTheme.lightTeal.withValues(alpha: 0.5) : null,
      child: ListTile(
        leading: Checkbox(
          value: isChecked,
          activeColor: AppTheme.teal,
          onChanged: (v) {
            setState(() {
              if (v == true) {
                _checkedIds.add(w.id);
              } else {
                _checkedIds.remove(w.id);
              }
            });
          },
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                w.word,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 17),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isPlaying)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.graphic_eq, color: AppTheme.teal, size: 18),
              ),
            if (w.isLongTerm)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.emoji_events, color: Colors.amber, size: 16),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (w.meaning.isNotEmpty)
              Text(w.meaning,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(
                  DateFormat('M/d').format(w.createdAt),
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
                const SizedBox(width: 8),
                if (w.tags.isNotEmpty)
                  Flexible(
                    child: Text(
                      w.tags.map((t) => '#$t').join(' '),
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.teal),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const SizedBox(width: 8),
                Icon(Icons.headphones,
                    size: 11, color: Colors.grey.shade400),
                Text(' ${w.playCount}',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
          ],
        ),
        trailing: IconButton(
          icon: Icon(
            isPlaying ? Icons.volume_up : Icons.play_circle_outline,
            color: AppTheme.deepIndigo,
            size: 28,
          ),
          onPressed: _isPlayingAll ? null : () => _playSingle(w),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.playlist_play, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            '조건에 맞는 단어가 없어요\n녹음 탭에서 단어를 캡처해 보세요!',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}
