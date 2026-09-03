import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 품사별 뜻 항목
class DictMeaning {
  final String partOfSpeech; // noun, verb, adjective ...
  final String definition;   // 영어 정의
  final String? korean;      // 한국어 번역 (품사+정의 기준)
  final String? example;     // 예문

  const DictMeaning({
    required this.partOfSpeech,
    required this.definition,
    this.korean,
    this.example,
  });

  /// 화면 표시용 레이블: "(noun) 인사" 형태
  String get label {
    final pos = partOfSpeech.isNotEmpty ? '($partOfSpeech) ' : '';
    return '$pos${korean ?? definition}';
  }
}

/// 사전 조회 전체 결과
class DictResult {
  final String? meaning;          // 최종 선택된 뜻 (저장용)
  final String? audioUrl;         // 원어민 발음 mp3
  final List<DictMeaning> allMeanings; // 선택 가능한 전체 뜻 목록

  const DictResult({
    this.meaning,
    this.audioUrl,
    this.allMeanings = const [],
  });
}

/// 단어 뜻 + 원어민 발음 자동 조회
/// 1) dictionaryapi.dev → 품사별 영어 정의 전체 목록 + 발음 mp3
/// 2) MyMemory 번역 API → 한글 번역 (단, 품질 필터링 강화)
class DictionaryService {

  static Future<DictResult> lookup(String word) async {
    final w = word.trim();
    if (w.isEmpty) return const DictResult();

    // 영어 사전 데이터 먼저 가져오기 (더 신뢰도 높음)
    final engData = await _lookupEnglishData(w);

    // 한국어 번역: 단어가 한 단어(공백 없음)이고 영어 단어일 때만 요청
    // MyMemory는 문맥(문장)이 들어오면 엉뚱한 결과를 낼 수 있어서 필터링
    String? koreanTranslation;
    if (_isSingleWord(w)) {
      koreanTranslation = await _lookupKorean(w);
    }

    // 품사별 뜻 목록 구성
    final List<DictMeaning> allMeanings = [];

    if (engData.meanings.isNotEmpty) {
      for (final m in engData.meanings) {
        allMeanings.add(DictMeaning(
          partOfSpeech: m.partOfSpeech,
          definition: m.definition,
          korean: m == engData.meanings.first ? koreanTranslation : null,
          example: m.example,
        ));
      }
    } else if (koreanTranslation != null) {
      // 사전에 없는 단어지만 번역은 됐을 때
      allMeanings.add(DictMeaning(
        partOfSpeech: '',
        definition: w,
        korean: koreanTranslation,
      ));
    }

    // 기본 선택값: 첫 번째 뜻을 한국어 + 영어 정의로 조합
    String? defaultMeaning;
    if (allMeanings.isNotEmpty) {
      final first = allMeanings.first;
      final parts = <String>[];
      if (koreanTranslation != null && koreanTranslation.isNotEmpty) {
        parts.add(koreanTranslation);
      }
      if (first.definition.isNotEmpty) {
        parts.add('(${first.partOfSpeech.isNotEmpty ? first.partOfSpeech : "def"}) ${first.definition}');
      }
      defaultMeaning = parts.isNotEmpty ? parts.join('\n') : null;
    }

    return DictResult(
      meaning: defaultMeaning,
      audioUrl: engData.audioUrl,
      allMeanings: allMeanings,
    );
  }

  /// 단일 단어 여부 체크 (공백, 하이픈 허용, 숫자 제외)
  static bool _isSingleWord(String w) {
    // 공백이 2개 이상이면 구문으로 판단
    final spaceCount = w.split(' ').length - 1;
    if (spaceCount >= 2) return false;
    // 숫자만 있거나 특수문자 위주면 제외
    if (RegExp(r'^\d+$').hasMatch(w)) return false;
    return true;
  }

  /// 한글 번역 (MyMemory API) — 품질 필터링 강화
  static Future<String?> _lookupKorean(String word) async {
    try {
      final uri = Uri.https('api.mymemory.translated.net', '/get', {
        'q': word,
        'langpair': 'en|ko',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body);
      final translated = data['responseData']?['translatedText']?.toString().trim();
      if (translated == null || translated.isEmpty) return null;

      // 품질 필터: 원문과 동일하면 번역 실패
      if (translated.toLowerCase() == word.toLowerCase()) return null;

      // 품질 필터: 번역 결과가 영어 단어보다 훨씬 길면 (문장이 들어온 경우)
      // 예) "hello" → "제 이름은 Azlan입니다" 같은 경우 차단
      // 원래 단어 길이의 4배 이상이면 엉뚱한 결과로 판단
      if (translated.length > word.length * 4 + 10) return null;

      // 품질 점수 확인 (0.0 ~ 1.0, 낮으면 신뢰도 낮음)
      final matchScore = (data['responseData']?['match'] as num?)?.toDouble() ?? 0.0;
      if (matchScore < 0.05) return null; // 거의 매칭 안 되는 경우 제외

      // 알림 메시지가 포함된 경우 제외 (MyMemory 무료 한도 초과 메시지 등)
      if (translated.contains('PLEASE') || translated.contains('LIMIT')) return null;

      return translated;
    } catch (e) {
      if (kDebugMode) debugPrint('Korean translation error: $e');
      return null;
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

      // ─── 원어민 발음 오디오 URL (미국 발음 우선) ───
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

      // ─── 품사별 정의 전체 추출 (최대 6개) ───
      final List<_MeaningItem> meanings = [];
      for (final entry in data) {
        final entryMeanings = entry['meanings'];
        if (entryMeanings is! List) continue;
        for (final m in entryMeanings) {
          final pos = m['partOfSpeech']?.toString() ?? '';
          final defs = m['definitions'];
          if (defs is! List) continue;
          for (final d in defs.take(2)) { // 품사당 최대 2개
            final def = d['definition']?.toString() ?? '';
            final ex = d['example']?.toString();
            if (def.isEmpty) continue;
            meanings.add(_MeaningItem(
              partOfSpeech: pos,
              definition: def,
              example: ex,
            ));
            if (meanings.length >= 6) break; // 전체 최대 6개
          }
          if (meanings.length >= 6) break;
        }
        if (meanings.length >= 6) break;
      }

      return _EnglishData(meanings: meanings, audioUrl: audioUrl);
    } catch (e) {
      if (kDebugMode) debugPrint('Dictionary lookup error: $e');
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
