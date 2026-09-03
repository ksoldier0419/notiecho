import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

/// 내 목소리 녹음 서비스 (웹: blob url, 모바일: 파일 경로)
class VoiceRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;

  bool get isRecording => _isRecording;

  Future<bool> hasPermission() async {
    try {
      return await _recorder.hasPermission();
    } catch (_) {
      return false;
    }
  }

  Future<bool> start() async {
    try {
      // 이미 녹음 중이면 먼저 중단
      if (_isRecording) {
        await _recorder.cancel();
        _isRecording = false;
      }

      // 권한 확인
      if (!await _recorder.hasPermission()) {
        if (kDebugMode) debugPrint('[VoiceRecorder] No permission');
        return false;
      }

      // 모바일: 반드시 실제 파일 경로 지정 (빈 문자열 금지)
      String? path;
      if (!kIsWeb) {
        final dir = await getApplicationDocumentsDirectory();
        path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        if (kDebugMode) debugPrint('[VoiceRecorder] Recording to: $path');
      }
      // 웹은 path=null → 메모리 blob

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path ?? '',
      );
      _isRecording = true;
      if (kDebugMode) debugPrint('[VoiceRecorder] Started');
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[VoiceRecorder] start error: $e');
      _isRecording = false;
      return false;
    }
  }

  /// 녹음 종료 → 저장된 경로(or blob url) 반환
  Future<String?> stop() async {
    if (!_isRecording) return null;
    try {
      final path = await _recorder.stop();
      _isRecording = false;
      if (kDebugMode) debugPrint('[VoiceRecorder] Stopped, path: $path');
      return path;
    } catch (e) {
      if (kDebugMode) debugPrint('[VoiceRecorder] stop error: $e');
      _isRecording = false;
      return null;
    }
  }

  Future<void> cancel() async {
    try {
      if (_isRecording) {
        await _recorder.cancel();
      }
    } catch (_) {}
    _isRecording = false;
  }

  void dispose() {
    _recorder.dispose();
  }
}
