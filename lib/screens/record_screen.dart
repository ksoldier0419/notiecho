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

/// 녹음 탭: 녹음 → STT 인식 → 정정 → 발음 확인 → 태그 → 저장
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
  bool _isListening = false;
  bool _hasResult = false;
  bool _lookingUp = false;
  bool _permissionDenied = false;
  String? _myVoicePath;
  String? _nativeAudioUrl;
  final Set<String> _selectedTags = {};
  String _statusMessage = '녹음 버튼을 누르고 단어를 말하세요';

  @override
  void initState() {
    super.initState();
    _pulseCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat();
    _requestPermissionAndInit();
  }

  /// 마이크 권한 요청 → 권한 허용 시 STT 초기화
  Future<void> _requestPermissionAndInit() async {
    // 웹은 브라우저가 권한을 처리하므로 바로 초기화
    if (kIsWeb) {
      await _initSpeech();
      return;
    }

    final status = await Permission.microphone.status;

    if (status.isGranted) {
      await _initSpeech();
    } else if (status.isPermanentlyDenied) {
      // 설정 앱에서만 허용 가능한 상태
      if (mounted) {
        setState(() {
          _permissionDenied = true;
          _statusMessage = '마이크 권한이 차단되었습니다. 설정에서 허용해 주세요.';
        });
      }
    } else {
      // 권한 요청 팝업 표시
      final result = await Permission.microphone.request();
      if (result.isGranted) {
        await _initSpeech();
      } else if (result.isPermanentlyDenied) {
        if (mounted) {
          setState(() {
            _permissionDenied = true;
            _statusMessage = '마이크 권한이 차단되었습니다. 설정에서 허용해 주세요.';
          });
        }
      } else {
        // 거부됨 (팝업에서 취소)
        if (mounted) {
          setState(() {
            _permissionDenied = true;
            _statusMessage = '마이크 권한이 필요합니다. 버튼을 눌러 다시 허용해 주세요.';
          });
        }
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _initSpeech() async {
    try {
      _sttAvailable = await _speech.initialize(
        onStatus: (status) {
          if (kDebugMode) debugPrint('[STT] status: $status');
          if (status == 'notListening' || status == 'done') {
            if (mounted && _isListening) _stopListening();
          }
        },
        onError: (e) {
          if (kDebugMode) debugPrint('[STT] error: ${e.errorMsg}');
          if (mounted) {
            setState(() {
              _isListening = false;
              // 권한 오류일 경우 구체적인 안내
              if (e.errorMsg.contains('permission') ||
                  e.errorMsg.contains('audio')) {
                _statusMessage = '마이크 권한을 허용해 주세요 (설정 > 앱 > 마이크)';
              } else {
                _statusMessage = '음성 인식 오류 — 다시 시도하거나 직접 입력하세요';
              }
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

  Future<void> _startListening() async {
    // 권한이 거부된 상태라면 재요청 또는 설정으로 안내
    if (!kIsWeb && _permissionDenied) {
      final status = await Permission.microphone.status;
      if (status.isPermanentlyDenied) {
        _showGoToSettingsDialog();
        return;
      }
      // 다시 한번 요청 시도
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
      _statusMessage = '듣고 있어요... 단어를 말하세요 🎙';
      _isListening = true;
      _permissionDenied = false;
    });

    // 내 목소리 녹음 시작 (STT와 동시)
    await _recorder.start();

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
    } else {
      // STT 불가 시에도 내 목소리 녹음은 계속 (직접 입력 가능)
      if (kDebugMode) debugPrint('[STT] not available, recording voice only');
    }
  }

  void _showGoToSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('마이크 권한 필요'),
        content: const Text(
          '음성 인식을 사용하려면 마이크 권한이 필요합니다.\n\n'
          '설정 앱 > NotiEcho > 권한 > 마이크를 "허용"으로 변경해 주세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings(); // permission_handler 제공
            },
            child: const Text('설정 열기'),
          ),
        ],
      ),
    );
  }

  Future<void> _stopListening() async {
    try {
      await _speech.stop();
    } catch (_) {}
    final voicePath = await _recorder.stop();

    if (!mounted) return;
    setState(() {
      _isListening = false;
      _myVoicePath = voicePath;
      _hasResult = true;
      _statusMessage = _wordCtrl.text.trim().isEmpty
          ? '인식된 단어가 없어요 — 직접 입력해도 됩니다'
          : '인식 결과를 확인하고 정정하세요 ✏️';
    });

    if (_wordCtrl.text.trim().isNotEmpty) {
      _lookupMeaning();
    }
  }

  Future<void> _lookupMeaning() async {
    final word = _wordCtrl.text.trim();
    if (word.isEmpty) return;
    setState(() => _lookingUp = true);
    final result = await DictionaryService.lookup(word);
    if (!mounted) return;
    setState(() {
      _lookingUp = false;
      _nativeAudioUrl = result.audioUrl;
      if (result.meaning != null && _meaningCtrl.text.trim().isEmpty) {
        _meaningCtrl.text = result.meaning!;
      }
    });
  }

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

    // 저장 직후 원어민 발음 1회 재생 (에코!)
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
      _selectedTags.clear();
      _statusMessage = '녹음 버튼을 누르고 단어를 말하세요';
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _wordCtrl.dispose();
    _meaningCtrl.dispose();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<WordStore>();
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.graphic_eq, size: 22),
            const SizedBox(width: 8),
            const Text('NotiEcho',
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          ],
        ),
      ),
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
            _buildRecordButton(),
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

  Widget _buildRecordButton() {
    return GestureDetector(
      onTap: _isListening ? _stopListening : _startListening,
      child: SizedBox(
        width: 200,
        height: 200,
        child: AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (context, child) {
            return Stack(
              alignment: Alignment.center,
              children: [
                // 에코 링 애니메이션
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
                // 메인 버튼
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
                    _isListening ? Icons.stop_rounded : Icons.mic_rounded,
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

  Widget _buildResultCard(WordStore store) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onSubmitted: (_) => _lookupMeaning(),
            ),
            const SizedBox(height: 10),
            // 발음 듣기 버튼 영역
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.deepIndigo,
                      side: const BorderSide(color: AppTheme.teal),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.volume_up, size: 20),
                    label: Text(_nativeAudioUrl != null ? '원어민 발음' : '표준 발음',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () {
                      final w = _wordCtrl.text.trim();
                      if (w.isNotEmpty) {
                        AudioService()
                            .pronounce(w, audioUrl: _nativeAudioUrl);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _myVoicePath != null
                          ? AppTheme.indigo
                          : Colors.grey,
                      side: BorderSide(
                          color: _myVoicePath != null
                              ? AppTheme.indigo
                              : Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.record_voice_over, size: 20),
                    label: const Text('내 녹음',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: _myVoicePath == null
                        ? null
                        : () => AudioService().playMyVoice(_myVoicePath!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('뜻', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                if (_lookingUp)
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _lookupMeaning,
                  icon: const Icon(Icons.search, size: 16),
                  label: const Text('사전 조회', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            TextField(
              controller: _meaningCtrl,
              maxLines: 2,
              minLines: 1,
              decoration: InputDecoration(
                hintText: '뜻 입력 (자동 조회 또는 직접 입력)',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('태그 선택',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            TagSelector(
              allTags: store.tags,
              selected: _selectedTags,
              onChanged: (tags) =>
                  setState(() => _selectedTags
                    ..clear()
                    ..addAll(tags)),
              onCreateTag: (t) => store.addTag(t),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isListening ? null : _save,
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
                    '논문을 읽다가 모르는 단어가 나오면 바로 녹음하세요.\n입 밖으로 소리 내어 따라 말할수록 기억에 오래 남습니다!',
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
