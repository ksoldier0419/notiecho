import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 단어 뜻 자동 조회
/// 1) MyMemory 번역 API → 한글 뜻 (구문/여러 단어도 지원)
/// 2) dictionaryapi.dev → 영어 정의 (단일 단어)
/// 두 결과를 합쳐서 반환
class DictionaryService {
  static Future<String?> lookupMeaning(String word) async {
    final w = word.trim();
    if (w.isEmpty) return null;

    final results = await Future.wait([
      _lookupKorean(w),
      _lookupEnglishDef(w),
    ]);

    final korean = results[0];
    final english = results[1];

    final parts = <String>[];
    if (korean != null && korean.isNotEmpty) parts.add(korean);
    if (english != null && english.isNotEmpty) parts.add(english);
    return parts.isEmpty ? null : parts.join('\n');
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
      // 번역 실패 시 원문 그대로 돌아오는 경우 제외
      if (translated.toLowerCase() == word.toLowerCase()) return null;
      return translated;
    } catch (e) {
      if (kDebugMode) debugPrint('Korean translation error: $e');
      return null;
    }
  }

  /// 영어 정의 (dictionaryapi.dev - 단일 단어 위주)
  static Future<String?> _lookupEnglishDef(String word) async {
    try {
      final w = word.toLowerCase();
      final uri =
          Uri.https('api.dictionaryapi.dev', '/api/v2/entries/en/$w');
      var res = await http.get(uri).timeout(const Duration(seconds: 6));

      // 구문(여러 단어)이 실패하면 하이픈 연결로 재시도 (예: high school → high-school)
      if (res.statusCode != 200 && w.contains(' ')) {
        final hyphen = w.replaceAll(RegExp(r'\s+'), '-');
        final uri2 =
            Uri.https('api.dictionaryapi.dev', '/api/v2/entries/en/$hyphen');
        res = await http.get(uri2).timeout(const Duration(seconds: 6));
      }
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body);
      if (data is! List || data.isEmpty) return null;
      final meanings = data[0]['meanings'];
      if (meanings is! List || meanings.isEmpty) return null;

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
      return parts.isEmpty ? null : parts.join('\n');
    } catch (e) {
      if (kDebugMode) debugPrint('Dictionary lookup error: $e');
      return null;
    }
  }
}
