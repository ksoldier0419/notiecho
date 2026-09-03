import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';

/// TTS(AI 목소리) + 내 목소리 재생 통합 서비스
class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _player = AudioPlayer();

  bool _ttsReady = false;
  double _speechRate = 0.45;

  Future<void> init() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(_speechRate);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      // 재생 완료를 await 할 수 있게 설정
      await _tts.awaitSpeakCompletion(true);
      _ttsReady = true;
    } catch (e) {
      if (kDebugMode) debugPrint('TTS init error: $e');
    }
  }

  double get speechRate => _speechRate;

  Future<void> setSpeechRate(double rate) async {
    _speechRate = rate;
    try {
      await _tts.setSpeechRate(rate);
    } catch (_) {}
  }

  /// AI 목소리로 단어 발음 (완료까지 대기)
  Future<void> speak(String text) async {
    if (!_ttsReady) await init();
    try {
      await _tts.speak(text);
    } catch (e) {
      if (kDebugMode) debugPrint('TTS speak error: $e');
    }
  }

  Future<void> stopSpeak() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  /// 내 목소리(녹음 파일) 재생 - 완료까지 대기
  Future<void> playMyVoice(String path) async {
    try {
      final completer = Completer<void>();
      late StreamSubscription sub;
      sub = _player.onPlayerComplete.listen((_) {
        sub.cancel();
        if (!completer.isCompleted) completer.complete();
      });
      if (kIsWeb || path.startsWith('http') || path.startsWith('blob:')) {
        await _player.play(UrlSource(path));
      } else {
        await _player.play(DeviceFileSource(path));
      }
      // 최대 10초 안전장치
      await completer.future.timeout(const Duration(seconds: 10), onTimeout: () {
        sub.cancel();
      });
    } catch (e) {
      if (kDebugMode) debugPrint('playMyVoice error: $e');
    }
  }

  Future<void> stopAll() async {
    await stopSpeak();
    try {
      await _player.stop();
    } catch (_) {}
  }
}
