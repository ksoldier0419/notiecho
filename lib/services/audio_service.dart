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

  /// 원어민 발음 재생 우선순위:
  /// 1) 구글 번역 TTS mp3 (구글 검색 발음과 동일 계열의 신경망 음성, 구문도 지원)
  /// 2) 사전 API 원어민 녹음 mp3
  /// 3) 기기 TTS 폴백
  Future<void> pronounce(String word, {String? audioUrl}) async {
    final w = word.trim();
    if (w.isEmpty) return;

    // 1순위: 구글 TTS mp3 (고품질 신경망 음성)
    final gUrl = _googleTtsUrl(w);
    if (await _playUrl(gUrl)) return;

    // 2순위: 사전 원어민 녹음
    if (audioUrl != null && audioUrl.isNotEmpty) {
      if (await _playUrl(audioUrl)) return;
    }

    // 3순위: 기기 TTS
    await speak(w);
  }

  /// 구글 번역 TTS mp3 URL 생성
  /// 웹: 같은 서버의 프록시 경유 (브라우저 Referer로 인한 구글 차단 우회)
  /// 모바일: 구글 직접 호출 (네이티브 요청은 Referer가 없어 정상 동작)
  String _googleTtsUrl(String text) {
    if (kIsWeb) {
      // 현재 페이지 origin 기준 절대 URL (프리뷰/배포 어디서든 동작)
      return Uri.base
          .resolveUri(Uri(path: '/tts', queryParameters: {'q': text}))
          .toString();
    }
    return Uri.https('translate.google.com', '/translate_tts', {
      'ie': 'UTF-8',
      'tl': 'en',
      'client': 'tw-ob',
      'q': text,
    }).toString();
  }

  /// AI 목소리(TTS)로 단어 발음 — 영어 (완료까지 대기)
  Future<void> speak(String text) async {
    if (!_ttsReady) await init();
    try {
      await _tts.setLanguage('en-US');
      await _tts.speak(text);
    } catch (e) {
      if (kDebugMode) debugPrint('TTS speak error: $e');
    }
  }

  /// 한국어 TTS로 뜻 읽기 (뜻만 재생 모드용)
  Future<void> speakKorean(String text) async {
    if (!_ttsReady) await init();
    try {
      // 뜻 텍스트에서 영어 정의 부분 제거 — "(noun) ..." 이후는 생략
      final cleanText = _extractKoreanPart(text);
      if (cleanText.isEmpty) return;
      await _tts.setLanguage('ko-KR');
      await _tts.setSpeechRate(0.5);
      await _tts.speak(cleanText);
      // 영어 모드로 복원
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(_speechRate);
    } catch (e) {
      if (kDebugMode) debugPrint('Korean TTS speak error: $e');
      // 복원 시도
      try { await _tts.setLanguage('en-US'); } catch (_) {}
    }
  }

  /// 뜻 문자열에서 한국어 부분만 추출
  /// 예) "인사하다\n(verb) used to greet..." → "인사하다"
  String _extractKoreanPart(String meaning) {
    final lines = meaning.split('\n');
    final koreanLines = lines.where((l) {
      final trimmed = l.trim();
      if (trimmed.isEmpty) return false;
      // (품사) 로 시작하는 영어 정의 줄 제외
      if (trimmed.startsWith('(') && RegExp(r'^\([a-z]+\)').hasMatch(trimmed)) {
        return false;
      }
      // "예)" 로 시작하는 예문 제외
      if (trimmed.startsWith('예)')) return false;
      return true;
    }).toList();
    return koreanLines.isNotEmpty ? koreanLines.join(', ') : meaning.split('\n').first;
  }

  Future<void> stopSpeak() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  /// URL 오디오 재생 (발음 mp3) - 완료까지 대기, 성공 여부 반환
  Future<bool> _playUrl(String url) async {
    StreamSubscription? sub;
    try {
      final completer = Completer<void>();
      sub = _player.onPlayerComplete.listen((_) {
        if (!completer.isCompleted) completer.complete();
      });
      await _player.play(UrlSource(url));
      await completer.future.timeout(const Duration(seconds: 8));
      await sub.cancel();
      return true;
    } on TimeoutException {
      // 재생은 시작됐으나 완료 이벤트만 누락된 경우 → 성공 처리
      await sub?.cancel();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('playUrl error: $e');
      await sub?.cancel();
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
