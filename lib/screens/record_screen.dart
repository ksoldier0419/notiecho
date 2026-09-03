import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/word_entry.dart';
import '../services/word_store.dart';
import '../services/audio_service.dart';
import '../services/voice_recorder.dart';
import '../services/dictionary_service.dart';
import '../theme.dart';
import '../widgets/tag_selector.dart';

/// 녹음 탭: STT 인식 → 정정 → 내 발음 별도 녹음 → 태그 → 저장
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen>
    with SingleTickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final VoiceRecorder _recorder = VoiceRecorder();
  final TextEditingController _wordCtrl = TextEditingController();
  final TextEditingController _meaningCtrl = TextEditingController();

  late AnimationController _pulseCtrl;

  bool _sttAvailable = false;
  bool _isListening = false;      // STT 듣는 중
  bool _isRecordingVoice = false; // 내 발음 녹음 중
  bool _hasResult = false;
  bool _lookingUp = false;
  bool _permissionDenied = false;
  String? _myVoicePath;
  String? _nativeAudioUrl;
  List<DictMeaning> _allMeanings = []; // 선택 가능한 전체 뜻 목록
  final Set<String> _selectedTags = {};
  String _statusMessage = '버튼을 누르고 단어를 말하세요';

  @override
  void initState() {
    super.initState();
    _pulseCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat();
    _requestPermissionAndInit();
  }

  // ─── 권한 요청 ───────────────────────────────────────────────
  Future<void> _requestPermissionAndInit() async {
    if (kIsWeb) {
      await _initSpeech();
      return;
    }
    final status = await Permission.microphone.status;
    if (status.isGranted) {
      await _initSpeech();
    } else if (status.isPermanentlyDenied) {
      if (mounted) {
        setState(() {
          _permissionDenied = true;
          _statusMessage = '마이크 권한이 차단되었습니다. 설정에서 허용해 주세요.';
        });
      }
    } else {
      final result = await Permission.microphone.request();
      if (result.isGranted) {
        await _initSpeech();
      } else {
        if (mounted) {
          setState(() {
            _permissionDenied = true;
            _statusMessage = result.isPermanentlyDenied
                ? '마이크 권한이 차단됩니다. 설정에서 허용해 주세요.'
                : '마이크 권한이 필요합니다. 아래 버튼으로 허용해 주세요.';
          });
        }
      }
    }
    if (mounted) setState(() {});
  }

  // ─── STT 초기화 ──────────────────────────────────────────────
  Future<void> _initSpeech() async {
    try {
      _sttAvailable = await _speech.initialize(
        onStatus: (status) {
          if (kDebugMode) debugPrint('[STT] status: $status');
          if ((status == 'notListening' || status == 'done') &&
              mounted && _isListening) {
            _stopStt();
          }
        },
        onError: (e) {
          if (kDebugMode) debugPrint('[STT] error: ${e.errorMsg}');
          if (mounted) {
            setState(() {
              _isListening = false;
              _statusMessage = e.errorMsg.contains('permission') ||
                      e.errorMsg.contains('audio')
                  ? '마이크 권한을 허용해 주세요 (설정 > 앱 > 마이크)'
                  : '음성 인식 오류 — 다시 시도하거나 직접 입력하세요';
            });
          }
        },
      );
      if (kDebugMode) debugPrint('[STT] available: $_sttAvailable');
    } catch (e) {
      if (kDebugMode) debugPrint('[STT] init exception: $e');
      _sttAvailable = false;
    }
    if (mounted) setState(() {});
  }

  // ─── STT 시작 (단어 인식 전용, 녹음과 분리) ──────────────────
  Future<void> _startStt() async {
    if (!kIsWeb && _permissionDenied) {
      final status = await Permission.microphone.status;
      if (status.isPermanentlyDenied) {
        _showGoToSettingsDialog();
        return;
      }
      await _requestPermissionAndInit();
      if (!_sttAvailable) return;
    }

    AudioService().stopAll();
    setState(() {
      _hasResult = false;
      _wordCtrl.clear();
      _meaningCtrl.clear();
      _myVoicePath = null;
      _nativeAudioUrl = null;
      _allMeanings = [];
      _statusMessage = '듣고 있어요... 단어를 말하세요 🎙';
      _isListening = true;
      _permissionDenied = false;
    });

    if (_sttAvailable) {
      await _speech.listen(
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          listenMode: stt.ListenMode.search,
          localeId: 'en_US',
        ),
        onResult: (result) {
          if (mounted) {
            setState(() => _wordCtrl.text = result.recognizedWords);
          }
        },
      );
    }
  }

  // ─── STT 중단 ─────────────────────────────────────────────────
  Future<void> _stopStt() async {
    try {
      await _speech.stop();
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _isListening = false;
      _hasResult = true;
      _statusMessage = _wordCtrl.text.trim().isEmpty
          ? '인식된 단어가 없어요 — 직접 입력해도 됩니다'
          : '인식 결과를 확인하고 내 발음을 녹음하세요 🎤';
    });

    if (_wordCtrl.text.trim().isNotEmpty) {
      _lookupMeaning();
    }
  }

  // ─── 내 발음 녹음 시작 ────────────────────────────────────────
  Future<void> _startMyVoiceRecording() async {
    // STT가 켜져 있으면 먼저 중단
    if (_isListening) {
      try { await _speech.stop(); } catch (_) {}
      setState(() => _isListening = false);
      await Future.delayed(const Duration(milliseconds: 300));
    }

    setState(() {
      _isRecordingVoice = true;
      _myVoicePath = null;
      _statusMessage = '내 발음 녹음 중... 🔴 단어를 크게 말해보세요';
    });

    final started = await _recorder.start();
    if (!started) {
      if (mounted) {
        setState(() {
          _isRecordingVoice = false;
          _statusMessage = '녹음 시작 실패 — 마이크 권한을 확인해 주세요';
        });
      }
    }
  }

  // ─── 내 발음 녹음 중단 ────────────────────────────────────────
  Future<void> _stopMyVoiceRecording() async {
    final path = await _recorder.stop();
    if (!mounted) return;
    setState(() {
      _isRecordingVoice = false;
      _myVoicePath = path;
      _statusMessage = path != null
          ? '녹음 완료! ▶ 버튼으로 들어보세요 ✅'
          : '녹음 실패 — 다시 시도해 주세요';
    });
    if (kDebugMode) debugPrint('[MyVoice] saved to: $path');
  }

  // ─── 뜻 조회 ─────────────────────────────────────────────────
  Future<void> _lookupMeaning() async {
    final word = _wordCtrl.text.trim();
    if (word.isEmpty) return;
    setState(() {
      _lookingUp = true;
      _allMeanings = [];
    });
    final result = await DictionaryService.lookup(word);
    if (!mounted) return;
    setState(() {
      _lookingUp = false;
      _nativeAudioUrl = result.audioUrl;
      _allMeanings = result.allMeanings;
      // 뜻 필드가 비어있을 때만 기본값 채움
      if (result.meaning != null && _meaningCtrl.text.trim().isEmpty) {
        _meaningCtrl.text = result.meaning!;
      }
    });
  }

  // ─── 저장 ─────────────────────────────────────────────────────
  Future<void> _save() async {
    final word = _wordCtrl.text.trim();
    if (word.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('단어를 입력해 주세요')),
      );
      return;
    }
    final store = context.read<WordStore>();
    final entry = WordEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      word: word,
      meaning: _meaningCtrl.text.trim(),
      tags: _selectedTags.toList(),
      myVoicePath: _myVoicePath,
      nativeAudioUrl: _nativeAudioUrl,
    );
    await store.addWord(entry);

    AudioService().pronounce(word, audioUrl: _nativeAudioUrl);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"$word" 저장 완료! 🔊 발음을 따라 말해보세요'),
        backgroundColor: AppTheme.teal,
      ),
    );
    setState(() {
      _hasResult = false;
      _wordCtrl.clear();
      _meaningCtrl.clear();
      _myVoicePath = null;
      _nativeAudioUrl = null;
      _allMeanings = [];
      _selectedTags.clear();
      _statusMessage = '버튼을 누르고 단어를 말하세요';
    });
  }

  void _showGoToSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('마이크 권한 필요'),
        content: const Text(
          '음성 인식을 사용하려면 마이크 권한이 필요합니다.\n\n'
          '설정 앱 → NotiEcho → 권한 → 마이크 → "허용"으로 변경해 주세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('설정 열기'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _wordCtrl.dispose();
    _meaningCtrl.dispose();
    _recorder.dispose();
    super.dispose();
  }

  // ─── UI ───────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final store = context.watch<WordStore>();
    return Scaffold(

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Text(
              '오늘 캡처한 단어 ${store.todayCount}개',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 24),
            _buildSttButton(),
            const SizedBox(height: 16),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: _permissionDenied ? Colors.red.shade600 : null,
              ),
            ),
            if (_permissionDenied) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final status = await Permission.microphone.status;
                  if (status.isPermanentlyDenied) {
                    _showGoToSettingsDialog();
                  } else {
                    await _requestPermissionAndInit();
                  }
                },
                icon: const Icon(Icons.mic_off, size: 18),
                label: const Text('마이크 권한 허용하기'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade600,
                  side: BorderSide(color: Colors.red.shade300),
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (_hasResult || _isListening) _buildResultCard(store),
            if (!_hasResult && !_isListening) _buildManualEntryHint(),
          ],
        ),
      ),
    );
  }

  // ─── 뜻 선택 Chip ─────────────────────────────────────────────
  Widget _buildMeaningChip(DictMeaning m) {
    // 현재 뜻 필드에 이 항목이 선택됐는지 확인
    final isSelected = _meaningCtrl.text.contains(m.definition) ||
        (m.korean != null && _meaningCtrl.text.contains(m.korean!));

    final posColor = _posColor(m.partOfSpeech);

    return InkWell(
      onTap: () {
        // 탭하면 뜻 필드에 적용
        final parts = <String>[];
        if (m.korean != null && m.korean!.isNotEmpty) parts.add(m.korean!);
        parts.add('(${m.partOfSpeech.isNotEmpty ? m.partOfSpeech : "def"}) ${m.definition}');
        if (m.example != null) parts.add('예) ${m.example}');
        setState(() => _meaningCtrl.text = parts.join('\n'));
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 5),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.lightTeal.withValues(alpha: 0.35)
              : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.teal : Colors.grey.shade200,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 품사 뱃지
            if (m.partOfSpeech.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(right: 7, top: 1),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: posColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: posColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  m.partOfSpeech,
                  style: TextStyle(
                      fontSize: 10,
                      color: posColor,
                      fontWeight: FontWeight.bold),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (m.korean != null && m.korean!.isNotEmpty)
                    Text(
                      m.korean!,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  Text(
                    m.definition,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade600),
                  ),
                  if (m.example != null)
                    Text(
                      '예) ${m.example}',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade400,
                          fontStyle: FontStyle.italic),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: AppTheme.teal, size: 16),
          ],
        ),
      ),
    );
  }

  /// 품사별 색상
  Color _posColor(String pos) {
    switch (pos.toLowerCase()) {
      case 'noun': return Colors.blue.shade600;
      case 'verb': return Colors.green.shade600;
      case 'adjective': return Colors.orange.shade600;
      case 'adverb': return Colors.purple.shade600;
      case 'preposition': return Colors.red.shade400;
      case 'conjunction': return Colors.teal.shade600;
      default: return Colors.grey.shade600;
    }
  }

  // ─── STT 버튼 ─────────────────────────────────────────────────
  Widget _buildSttButton() {
    return GestureDetector(
      onTap: _isListening ? _stopStt : _startStt,
      child: SizedBox(
        width: 200,
        height: 200,
        child: AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (context, child) {
            return Stack(
              alignment: Alignment.center,
              children: [
                if (_isListening) ...[
                  _echoRing(_pulseCtrl.value),
                  _echoRing((_pulseCtrl.value + 0.5) % 1.0),
                ] else
                  Container(
                    width: 170,
                    height: 170,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppTheme.teal.withValues(alpha: 0.25), width: 2),
                    ),
                  ),
                Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _isListening
                          ? [Colors.red.shade400, Colors.red.shade700]
                          : [AppTheme.indigo, AppTheme.deepIndigo],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (_isListening ? Colors.red : AppTheme.indigo)
                            .withValues(alpha: 0.35),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isListening ? Icons.stop_rounded : Icons.record_voice_over_rounded,
                    color: Colors.white,
                    size: 56,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _echoRing(double t) {
    final size = 130 + t * 70;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppTheme.teal.withValues(alpha: (1 - t) * 0.6),
          width: 3,
        ),
      ),
    );
  }

  // ─── 결과 카드 ────────────────────────────────────────────────
  Widget _buildResultCard(WordStore store) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 단어 입력
            const Row(
              children: [
                Icon(Icons.edit_note, color: AppTheme.teal, size: 20),
                SizedBox(width: 6),
                Text('오리지널 단어로 정정',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _wordCtrl,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: '단어 입력...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onSubmitted: (_) => _lookupMeaning(),
            ),
            const SizedBox(height: 12),

            // 원어민 발음 버튼
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.deepIndigo,
                  side: const BorderSide(color: AppTheme.teal),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.volume_up, size: 20),
                label: Text(
                  _nativeAudioUrl != null ? '원어민 발음 듣기' : '표준 발음 듣기',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  final w = _wordCtrl.text.trim();
                  if (w.isNotEmpty) {
                    AudioService().pronounce(w, audioUrl: _nativeAudioUrl);
                  }
                },
              ),
            ),
            const SizedBox(height: 10),

            // 내 발음 녹음 버튼 (STT와 완전히 분리)
            _buildMyVoiceSection(),
            const SizedBox(height: 12),

            // 뜻
            Row(
              children: [
                const Text('뜻', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                if (_lookingUp)
                  const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _lookupMeaning,
                  icon: const Icon(Icons.search, size: 16),
                  label: const Text('사전 조회', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            // 뜻 선택 버튼 목록 (사전 조회 결과가 있을 때)
            if (_allMeanings.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '뜻 선택 (탭하면 적용)',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 6),
                    ..._allMeanings.map((m) => _buildMeaningChip(m)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _meaningCtrl,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(
                hintText: '뜻 입력 (위에서 선택하거나 직접 입력)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),

            // 태그
            const Text('태그 선택',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            TagSelector(
              allTags: store.tags,
              selected: _selectedTags,
              onChanged: (tags) => setState(() => _selectedTags
                ..clear()
                ..addAll(tags)),
              onCreateTag: (t) => store.addTag(t),
            ),
            const SizedBox(height: 16),

            // 저장 버튼
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_isListening || _isRecordingVoice) ? null : _save,
                icon: const Icon(Icons.save_alt),
                label: const Text('발음과 함께 저장',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 내 발음 녹음 섹션 ────────────────────────────────────────
  Widget _buildMyVoiceSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isRecordingVoice
            ? Colors.red.shade50
            : _myVoicePath != null
                ? AppTheme.lightTeal.withValues(alpha: 0.2)
                : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isRecordingVoice
              ? Colors.red.shade300
              : _myVoicePath != null
                  ? AppTheme.teal.withValues(alpha: 0.5)
                  : Colors.grey.shade300,
        ),
      ),
      child: Row(
        children: [
          // 녹음 시작/중지 버튼
          GestureDetector(
            onTap: _isRecordingVoice ? _stopMyVoiceRecording : _startMyVoiceRecording,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isRecordingVoice ? Colors.red : AppTheme.indigo,
              ),
              child: Icon(
                _isRecordingVoice ? Icons.stop : Icons.mic,
                color: Colors.white,
                size: 26,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isRecordingVoice
                      ? '🔴 녹음 중... 단어를 크게 말하세요'
                      : _myVoicePath != null
                          ? '✅ 내 발음 녹음 완료'
                          : '내 발음 녹음하기',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: _isRecordingVoice ? Colors.red.shade700 : null,
                  ),
                ),
                Text(
                  _isRecordingVoice
                      ? '버튼을 다시 눌러 중지'
                      : _myVoicePath != null
                          ? '▶ 버튼으로 내 녹음을 들을 수 있어요'
                          : '원어민 발음을 듣고 따라 말해보세요',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          // 내 녹음 재생 버튼
          if (_myVoicePath != null && !_isRecordingVoice)
            IconButton(
              icon: const Icon(Icons.play_circle_filled, size: 32),
              color: AppTheme.indigo,
              tooltip: '내 녹음 듣기',
              onPressed: () => AudioService().playMyVoice(_myVoicePath!),
            ),
        ],
      ),
    );
  }

  Widget _buildManualEntryHint() {
    return Column(
      children: [
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () {
            setState(() {
              _hasResult = true;
              _statusMessage = '직접 입력 모드 ✏️';
            });
          },
          icon: const Icon(Icons.keyboard, size: 18),
          label: const Text('음성 대신 직접 입력하기'),
        ),
        const SizedBox(height: 20),
        Card(
          color: AppTheme.lightTeal.withValues(alpha: 0.3),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.tips_and_updates, color: AppTheme.teal),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '① 버튼 눌러 단어 인식 → ② 원어민 발음 듣기 → ③ 내 발음 녹음 → ④ 저장\n'
                    '입 밖으로 소리 내어 말할수록 기억에 오래 남습니다!',
                    style: TextStyle(fontSize: 13, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
