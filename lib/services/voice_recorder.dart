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
      if (!await _recorder.hasPermission()) return false;
      String path = '';
      if (!kIsWeb) {
        final dir = await getApplicationDocumentsDirectory();
        path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      _isRecording = true;
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('Recorder start error: $e');
      return false;
    }
  }

  /// 녹음 종료 → 저장된 경로(or blob url) 반환
  Future<String?> stop() async {
    try {
      final path = await _recorder.stop();
      _isRecording = false;
      return path;
    } catch (e) {
      if (kDebugMode) debugPrint('Recorder stop error: $e');
      _isRecording = false;
      return null;
    }
  }

  Future<void> cancel() async {
    try {
      await _recorder.cancel();
    } catch (_) {}
    _isRecording = false;
  }

  void dispose() {
    _recorder.dispose();
  }
}
