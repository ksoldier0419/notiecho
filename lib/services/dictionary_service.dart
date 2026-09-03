import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 무료 사전 API로 단어 뜻 자동 조회 (dictionaryapi.dev)
class DictionaryService {
  static Future<String?> lookupMeaning(String word) async {
    final w = word.trim().toLowerCase();
    if (w.isEmpty) return null;
    try {
      final res = await http
          .get(Uri.parse('https://api.dictionaryapi.dev/api/v2/entries/en/$w'))
          .timeout(const Duration(seconds: 6));
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
