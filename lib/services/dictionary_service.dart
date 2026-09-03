import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 사전 조회 결과: 뜻 + 원어민 발음 오디오 URL
class DictResult {
  final String? meaning;
  final String? audioUrl;
  const DictResult({this.meaning, this.audioUrl});
}

/// 단어 뜻 + 원어민 발음 자동 조회
/// 1) MyMemory 번역 API → 한글 뜻 (구문/여러 단어도 지원)
/// 2) dictionaryapi.dev → 영어 정의 + 실제 원어민 발음 mp3 (단일 단어)
class DictionaryService {
  static Future<DictResult> lookup(String word) async {
    final w = word.trim();
    if (w.isEmpty) return const DictResult();

    final results = await Future.wait([
      _lookupKorean(w),
      _lookupEnglishData(w),
    ]);

    final korean = results[0] as String?;
    final english = results[1] as _EnglishData;

    final parts = <String>[];
    if (korean != null && korean.isNotEmpty) parts.add(korean);
    if (english.definition != null && english.definition!.isNotEmpty) {
      parts.add(english.definition!);
    }
    return DictResult(
      meaning: parts.isEmpty ? null : parts.join('\n'),
      audioUrl: english.audioUrl,
    );
  }

  /// 하위 호환용
  static Future<String?> lookupMeaning(String word) async {
    return (await lookup(word)).meaning;
  }

  /// 한글 번역 (MyMemory 무료 번역 API - 구문도 OK)
  static Future<String?> _lookupKorean(String word) async {
    try {
      final uri = Uri.https('api.mymemory.translated.net', '/get', {
        'q': word,
        'langpair': 'en|ko',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      final translated =
          data['responseData']?['translatedText']?.toString().trim();
      if (translated == null || translated.isEmpty) return null;
      if (translated.toLowerCase() == word.toLowerCase()) return null;
      return translated;
    } catch (e) {
      if (kDebugMode) debugPrint('Korean translation error: $e');
      return null;
    }
  }

  /// 영어 정의 + 원어민 발음 오디오 (dictionaryapi.dev)
  static Future<_EnglishData> _lookupEnglishData(String word) async {
    try {
      final w = word.toLowerCase();
      final uri =
          Uri.https('api.dictionaryapi.dev', '/api/v2/entries/en/$w');
      var res = await http.get(uri).timeout(const Duration(seconds: 6));

      // 구문(여러 단어)이 실패하면 하이픈 연결로 재시도
      if (res.statusCode != 200 && w.contains(' ')) {
        final hyphen = w.replaceAll(RegExp(r'\s+'), '-');
        final uri2 =
            Uri.https('api.dictionaryapi.dev', '/api/v2/entries/en/$hyphen');
        res = await http.get(uri2).timeout(const Duration(seconds: 6));
      }
      if (res.statusCode != 200) return const _EnglishData();

      final data = jsonDecode(res.body);
      if (data is! List || data.isEmpty) return const _EnglishData();

      // ─── 원어민 발음 오디오 URL 추출 (미국 발음 우선) ───
      String? audioUrl;
      for (final entry in data) {
        final phonetics = entry['phonetics'];
        if (phonetics is! List) continue;
        for (final p in phonetics) {
          final audio = p['audio']?.toString() ?? '';
          if (audio.isEmpty) continue;
          if (audio.contains('-us.')) {
            audioUrl = audio;
            break;
          }
          audioUrl ??= audio;
        }
        if (audioUrl != null && audioUrl.contains('-us.')) break;
      }

      // ─── 영어 정의 추출 ───
      String? definition;
      final meanings = data[0]['meanings'];
      if (meanings is List && meanings.isNotEmpty) {
        final parts = <String>[];
        for (final m in meanings.take(2)) {
          final pos = m['partOfSpeech']?.toString() ?? '';
          final defs = m['definitions'];
          if (defs is List && defs.isNotEmpty) {
            final def = defs[0]['definition']?.toString() ?? '';
            if (def.isNotEmpty) {
              parts.add(pos.isNotEmpty ? '($pos) $def' : def);
            }
          }
        }
        if (parts.isNotEmpty) definition = parts.join('\n');
      }

      return _EnglishData(definition: definition, audioUrl: audioUrl);
    } catch (e) {
      if (kDebugMode) debugPrint('Dictionary lookup error: $e');
      return const _EnglishData();
    }
  }
}

class _EnglishData {
  final String? definition;
  final String? audioUrl;
  const _EnglishData({this.definition, this.audioUrl});
}
