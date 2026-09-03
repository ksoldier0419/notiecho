import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';

/// TTS(AI 목소리) + 원어민 발음 mp3 + 내 목소리 재생 통합 서비스
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
      await _selectBestVoice();
      await _tts.setSpeechRate(_speechRate);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
      _ttsReady = true;
    } catch (e) {
      if (kDebugMode) debugPrint('TTS init error: $e');
    }
  }

  /// 고품질 보이스 자동 선택
  /// 웹(Chrome): "Google US English" / Android: 구글 TTS 엔진 en-US 보이스
  Future<void> _selectBestVoice() async {
    try {
      final voices = await _tts.getVoices;
      if (voices is! List) return;

      Map<String, String>? best;
      int bestScore = -1;

      for (final v in voices) {
        final name = (v['name'] ?? '').toString();
        final locale = (v['locale'] ?? '').toString();
        if (!locale.toLowerCase().startsWith('en')) continue;

        int score = 0;
        final lname = name.toLowerCase();
        final lloc = locale.toLowerCase();
        // 미국 영어 우선
        if (lloc.contains('us')) score += 4;
        // 고품질 보이스 키워드
        if (lname.contains('google us english')) score += 20;
        if (lname.contains('google')) score += 10;
        if (lname.contains('natural')) score += 8;
        if (lname.contains('neural')) score += 8;
        if (lname.contains('premium')) score += 6;
        if (lname.contains('enhanced')) score += 6;
        // 저품질 회피
        if (lname.contains('espeak')) score -= 10;
        if (lname.contains('compact')) score -= 5;

        if (score > bestScore) {
          bestScore = score;
          best = {'name': name, 'locale': locale};
        }
      }

      if (best != null && bestScore > 0) {
        await _tts.setVoice(best);
        if (kDebugMode) debugPrint('Selected TTS voice: ${best['name']}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Voice selection error: $e');
    }
  }

  double get speechRate => _speechRate;

  Future<void> setSpeechRate(double rate) async {
    _speechRate = rate;
    try {
      await _tts.setSpeechRate(rate);
    } catch (_) {}
  }

  /// 원어민 발음 재생: 사전 mp3가 있으면 그것을, 없으면 TTS
  /// → 구글 사전 수준의 실제 원어민 녹음 품질
  Future<void> pronounce(String word, {String? audioUrl}) async {
    if (audioUrl != null && audioUrl.isNotEmpty) {
      final ok = await _playUrl(audioUrl);
      if (ok) return;
    }
    await speak(word);
  }

  /// AI 목소리(TTS)로 단어 발음 (완료까지 대기)
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

  /// URL 오디오 재생 (원어민 발음 mp3) - 완료까지 대기, 성공 여부 반환
  Future<bool> _playUrl(String url) async {
    try {
      final completer = Completer<void>();
      late StreamSubscription sub;
      sub = _player.onPlayerComplete.listen((_) {
        sub.cancel();
        if (!completer.isCompleted) completer.complete();
      });
      await _player.play(UrlSource(url));
      await completer.future.timeout(const Duration(seconds: 8), onTimeout: () {
        sub.cancel();
      });
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('playUrl error: $e');
      return false;
    }
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
