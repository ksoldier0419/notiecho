import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

/// 내 목소리 녹음 서비스
/// - 잡음 제거 (noiseSuppress, echoCancel, autoGain)
/// - 무음 구간 자동 종료 (silence detection via amplitude)
class VoiceRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;

  // 무음 감지 설정
  static const double _silenceThreshold = -35.0; // dB (이보다 낮으면 무음)
  static const int _silenceDurationMs = 2000;    // 2초 무음 지속 시 자동 종료
  static const int _minRecordingMs = 500;         // 최소 녹음 시간 (너무 빠른 종료 방지)

  Timer? _silenceTimer;
  Timer? _amplitudePoller;
  DateTime? _recordingStartTime;

  // 외부에서 자동 종료 이벤트 수신용 콜백
  void Function()? onSilenceDetected;
  void Function(double db)? onAmplitudeChanged;

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
      if (_isRecording) {
        await _recorder.cancel();
        _isRecording = false;
        _stopTimers();
      }

      if (!await _recorder.hasPermission()) {
        if (kDebugMode) debugPrint('[VoiceRecorder] No permission');
        return false;
      }

      String? path;
      if (!kIsWeb) {
        final dir = await getApplicationDocumentsDirectory();
        path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }

      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
          // 잡음 제거 3종 세트
          noiseSuppress: true,   // 배경 잡음 억제
          echoCancel: true,      // 에코 제거 (스피커 소리 역유입 방지)
          autoGain: true,        // 자동 게인 조절 (너무 작은 목소리 보정)
        ),
        path: path ?? '',
      );

      _isRecording = true;
      _recordingStartTime = DateTime.now();

      // 무음 감지 시작
      _startSilenceDetection();

      if (kDebugMode) debugPrint('[VoiceRecorder] Started → $path');
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[VoiceRecorder] start error: $e');
      _isRecording = false;
      return false;
    }
  }

  /// 무음 감지: 100ms마다 진폭 체크
  void _startSilenceDetection() {
    _silenceTimer?.cancel();
    _amplitudePoller?.cancel();

    _amplitudePoller = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      if (!_isRecording) return;
      try {
        final amp = await _recorder.getAmplitude();
        final db = amp.current;

        onAmplitudeChanged?.call(db);

        // 최소 녹음 시간 확인
        final elapsed = DateTime.now().difference(_recordingStartTime!).inMilliseconds;
        if (elapsed < _minRecordingMs) return;

        if (db < _silenceThreshold) {
          // 무음 감지 → 타이머 시작 (아직 안 켜진 경우)
          _silenceTimer ??= Timer(
            Duration(milliseconds: _silenceDurationMs),
            () {
              if (_isRecording) {
                if (kDebugMode) debugPrint('[VoiceRecorder] Silence detected → auto stop');
                onSilenceDetected?.call();
              }
            },
          );
        } else {
          // 소리 감지 → 무음 타이머 리셋
          _silenceTimer?.cancel();
          _silenceTimer = null;
        }
      } catch (_) {}
    });
  }

  void _stopTimers() {
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _amplitudePoller?.cancel();
    _amplitudePoller = null;
  }

  /// 녹음 종료 → 저장된 경로 반환
  Future<String?> stop() async {
    if (!_isRecording) return null;
    _stopTimers();
    try {
      final path = await _recorder.stop();
      _isRecording = false;
      if (kDebugMode) debugPrint('[VoiceRecorder] Stopped → $path');
      return path;
    } catch (e) {
      if (kDebugMode) debugPrint('[VoiceRecorder] stop error: $e');
      _isRecording = false;
      return null;
    }
  }

  Future<void> cancel() async {
    _stopTimers();
    try {
      if (_isRecording) await _recorder.cancel();
    } catch (_) {}
    _isRecording = false;
  }

  void dispose() {
    _stopTimers();
    _recorder.dispose();
  }
}
