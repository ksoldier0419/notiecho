import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 품사별 뜻 항목
class DictMeaning {
  final String partOfSpeech; // noun, verb, adjective ...
  final String definition;   // 영어 정의
  final String? korean;      // 한국어 번역
  final String? example;     // 예문

  const DictMeaning({
    required this.partOfSpeech,
    required this.definition,
    this.korean,
    this.example,
  });

  String get label {
    final pos = partOfSpeech.isNotEmpty ? '($partOfSpeech) ' : '';
    return '$pos${korean ?? definition}';
  }
}

/// 사전 조회 전체 결과
class DictResult {
  final String? meaning;
  final String? audioUrl;
  final List<DictMeaning> allMeanings;

  const DictResult({
    this.meaning,
    this.audioUrl,
    this.allMeanings = const [],
  });
}

class DictionaryService {

  static Future<DictResult> lookup(String word) async {
    final w = word.trim();
    if (w.isEmpty) return const DictResult();

    // 병렬 조회: 영어 사전 + 구글 번역
    final results = await Future.wait([
      _lookupEnglishData(w),
      _translateGoogle(w),
    ]);

    final engData = results[0] as _EnglishData;
    final koreanMap = results[1] as Map<String, String>; // pos → 한국어

    // 품사별 뜻 목록 구성
    final List<DictMeaning> allMeanings = [];

    if (engData.meanings.isNotEmpty) {
      for (final m in engData.meanings) {
        // 품사에 매칭되는 한국어 우선, 없으면 단어 전체 번역 사용
        final korean = koreanMap[m.partOfSpeech] ?? koreanMap['word'];
        allMeanings.add(DictMeaning(
          partOfSpeech: m.partOfSpeech,
          definition: m.definition,
          korean: korean,
          example: m.example,
        ));
      }
    } else {
      // 사전에 없는 단어: 번역만 있는 경우
      final korean = koreanMap['word'];
      if (korean != null) {
        allMeanings.add(DictMeaning(
          partOfSpeech: '',
          definition: w,
          korean: korean,
        ));
      }
    }

    // 기본 저장값: 한국어 + 첫번째 영어 정의
    String? defaultMeaning;
    if (allMeanings.isNotEmpty) {
      final first = allMeanings.first;
      final parts = <String>[];
      if (first.korean != null && first.korean!.isNotEmpty) {
        parts.add(first.korean!);
      }
      if (first.definition.isNotEmpty && first.definition != w) {
        final pos = first.partOfSpeech.isNotEmpty ? first.partOfSpeech : 'def';
        parts.add('($pos) ${first.definition}');
      }
      defaultMeaning = parts.isNotEmpty ? parts.join('\n') : null;
    }

    return DictResult(
      meaning: defaultMeaning,
      audioUrl: engData.audioUrl,
      allMeanings: allMeanings,
    );
  }

  /// Google Translate 무료 엔드포인트 (MyMemory 대체)
  /// 품사별 번역 + 단어 전체 번역 모두 반환
  /// 반환값: {'word': '안녕', 'noun': '인사', 'verb': '안녕하다', ...}
  static Future<Map<String, String>> _translateGoogle(String word) async {
    final Map<String, String> result = {};
    try {
      // ── 방법 1: Google Translate API v2 (무료, 단어 기본 번역) ──
      // dt=bd: 사전(품사별 번역), dt=t: 번역 텍스트
      // Uri.https는 queryParameters Map이므로 dt를 List로 처리해야 함
      final uri = Uri(
        scheme: 'https',
        host: 'translate.googleapis.com',
        path: '/translate_a/single',
        query: 'client=gtx&sl=en&tl=ko&dt=t&dt=bd&q=${Uri.encodeComponent(word)}',
      );
      final res = await http.get(uri,
        headers: {'User-Agent': 'Mozilla/5.0'},
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);

        // 기본 번역 (data[0][0][0])
        if (data is List && data.isNotEmpty) {
          final mainTranslation = data[0];
          if (mainTranslation is List && mainTranslation.isNotEmpty) {
            final firstPart = mainTranslation[0];
            if (firstPart is List && firstPart.isNotEmpty) {
              final translated = firstPart[0]?.toString().trim();
              if (translated != null &&
                  translated.isNotEmpty &&
                  translated.toLowerCase() != word.toLowerCase()) {
                result['word'] = translated;
              }
            }
          }

          // 품사별 번역 (data[1]: [[품사, [번역들...]], ...])
          if (data.length > 1 && data[1] is List) {
            for (final posGroup in data[1]) {
              if (posGroup is! List || posGroup.length < 2) continue;
              final pos = posGroup[0]?.toString() ?? '';
              final translations = posGroup[1];
              if (translations is List && translations.isNotEmpty) {
                final firstTr = translations[0]?.toString().trim();
                if (firstTr != null && firstTr.isNotEmpty) {
                  // 영어 품사명을 dictionaryapi.dev 형식에 맞게 정규화
                  final normalizedPos = _normalizePosKo(pos);
                  if (normalizedPos.isNotEmpty) {
                    result[normalizedPos] = firstTr;
                  }
                }
              }
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Dict] Google translate error: $e');
    }

    // 결과가 없으면 폴백: dt=t 만 사용하는 단순 번역
    if (result.isEmpty) {
      try {
        final uri2 = Uri.https('translate.googleapis.com', '/translate_a/single', {
          'client': 'gtx',
          'sl': 'en',
          'tl': 'ko',
          'dt': 't',
          'q': word,
        });
        final res2 = await http.get(uri2,
          headers: {'User-Agent': 'Mozilla/5.0'},
        ).timeout(const Duration(seconds: 5));
        if (res2.statusCode == 200) {
          final data2 = jsonDecode(res2.body);
          if (data2 is List && data2.isNotEmpty &&
              data2[0] is List && (data2[0] as List).isNotEmpty) {
            final segment = (data2[0] as List)[0];
            if (segment is List && segment.isNotEmpty) {
              final tr = segment[0]?.toString().trim();
              if (tr != null && tr.isNotEmpty &&
                  tr.toLowerCase() != word.toLowerCase()) {
                result['word'] = tr;
              }
            }
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[Dict] Google translate fallback error: $e');
      }
    }

    return result;
  }

  /// 구글 반환 품사명 → dictionaryapi.dev 품사명 정규화
  static String _normalizePosKo(String pos) {
    switch (pos.toLowerCase()) {
      case 'noun':        return 'noun';
      case 'verb':        return 'verb';
      case 'adjective':   return 'adjective';
      case 'adverb':      return 'adverb';
      case 'exclamation': return 'exclamation';
      case 'preposition': return 'preposition';
      case 'conjunction': return 'conjunction';
      case 'pronoun':     return 'pronoun';
      default:            return pos.isNotEmpty ? pos : '';
    }
  }

  /// 영어 정의 전체 목록 + 원어민 발음 오디오 (dictionaryapi.dev)
  static Future<_EnglishData> _lookupEnglishData(String word) async {
    try {
      final w = word.toLowerCase().trim();
      final uri = Uri.https('api.dictionaryapi.dev', '/api/v2/entries/en/$w');
      var res = await http.get(uri).timeout(const Duration(seconds: 6));

      if (res.statusCode != 200 && w.contains(' ')) {
        final hyphen = w.replaceAll(RegExp(r'\s+'), '-');
        final uri2 = Uri.https('api.dictionaryapi.dev', '/api/v2/entries/en/$hyphen');
        res = await http.get(uri2).timeout(const Duration(seconds: 6));
      }
      if (res.statusCode != 200) return const _EnglishData();

      final data = jsonDecode(res.body);
      if (data is! List || data.isEmpty) return const _EnglishData();

      // 원어민 발음 오디오 URL (미국 발음 우선)
      String? audioUrl;
      for (final entry in data) {
        final phonetics = entry['phonetics'];
        if (phonetics is! List) continue;
        for (final p in phonetics) {
          final audio = p['audio']?.toString() ?? '';
          if (audio.isEmpty) continue;
          if (audio.contains('-us.')) { audioUrl = audio; break; }
          audioUrl ??= audio;
        }
        if (audioUrl != null && audioUrl.contains('-us.')) break;
      }

      // 품사별 정의 전체 추출 (최대 6개)
      final List<_MeaningItem> meanings = [];
      for (final entry in data) {
        final entryMeanings = entry['meanings'];
        if (entryMeanings is! List) continue;
        for (final m in entryMeanings) {
          final pos = m['partOfSpeech']?.toString() ?? '';
          final defs = m['definitions'];
          if (defs is! List) continue;
          for (final d in defs.take(2)) {
            final def = d['definition']?.toString() ?? '';
            final ex = d['example']?.toString();
            if (def.isEmpty) continue;
            meanings.add(_MeaningItem(
              partOfSpeech: pos,
              definition: def,
              example: ex,
            ));
            if (meanings.length >= 6) break;
          }
          if (meanings.length >= 6) break;
        }
        if (meanings.length >= 6) break;
      }

      return _EnglishData(meanings: meanings, audioUrl: audioUrl);
    } catch (e) {
      if (kDebugMode) debugPrint('[Dict] English lookup error: $e');
      return const _EnglishData();
    }
  }
}

class _MeaningItem {
  final String partOfSpeech;
  final String definition;
  final String? example;
  const _MeaningItem({
    required this.partOfSpeech,
    required this.definition,
    this.example,
  });
}

class _EnglishData {
  final List<_MeaningItem> meanings;
  final String? audioUrl;
  const _EnglishData({this.meanings = const [], this.audioUrl});
}
