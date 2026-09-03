import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/word_entry.dart';
import '../services/word_store.dart';
import '../services/audio_service.dart';
import '../theme.dart';

/// 관리 탭: 통계 + 태그 관리 + 단어 관리 + 장기기억 창고
class ManageScreen extends StatefulWidget {
  const ManageScreen({super.key});

  @override
  State<ManageScreen> createState() => _ManageScreenState();
}

class _ManageScreenState extends State<ManageScreen> {
  @override
  Widget build(BuildContext context) {
    final store = context.watch<WordStore>();
    return Scaffold(
      appBar: AppBar(title: const Text('관리')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStats(store),
          const SizedBox(height: 16),
          _buildSectionHeader(Icons.label, '태그 관리'),
          _buildTagManager(store),
          const SizedBox(height: 16),
          _buildSectionHeader(Icons.emoji_events, '장기기억 창고 (${store.longTermCount})'),
          _buildWordList(store, 'long'),
          const SizedBox(height: 16),
          _buildSectionHeader(Icons.hourglass_bottom, '단기기억 단어 (${store.shortTermCount})'),
          _buildWordList(store, 'short'),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.deepIndigo),
          const SizedBox(width: 8),
          Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }

  // ─── 통계 ───
  Widget _buildStats(WordStore store) {
    return Card(
      color: AppTheme.deepIndigo,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _statItem('전체', store.totalCount, Icons.library_books),
            _statItem('오늘', store.todayCount, Icons.today),
            _statItem('단기', store.shortTermCount, Icons.hourglass_bottom),
            _statItem('장기 🏆', store.longTermCount, Icons.emoji_events),
          ],
        ),
      ),
    );
  }

  Widget _statItem(String label, int value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: AppTheme.lightTeal, size: 20),
        const SizedBox(height: 6),
        Text('$value',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }

  // ─── 태그 관리 ───
  Widget _buildTagManager(WordStore store) {
    if (store.tags.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('태그가 없습니다. 녹음 탭에서 단어 저장 시 태그를 만들 수 있어요.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: store.tags.map((tag) {
            final count =
                store.words.where((w) => w.tags.contains(tag)).length;
            return InputChip(
              label: Text('$tag ($count)'),
              deleteIcon: const Icon(Icons.close, size: 16),
              onDeleted: () => _confirmDeleteTag(store, tag),
              onPressed: () => _renameTagDialog(store, tag),
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _renameTagDialog(WordStore store, String tag) async {
    final ctrl = TextEditingController(text: tag);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('태그 이름 수정'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('수정')),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      await store.renameTag(tag, result.trim());
    }
  }

  Future<void> _confirmDeleteTag(WordStore store, String tag) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('"$tag" 태그 삭제'),
        content: const Text('태그만 삭제되고 단어는 유지됩니다. 삭제할까요?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok == true) await store.deleteTag(tag);
  }

  // ─── 단어 리스트 ───
  Widget _buildWordList(WordStore store, String stage) {
    final words = store.filter(stage: stage);
    if (words.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            stage == 'long'
                ? '아직 장기기억으로 승격된 단어가 없어요. 시험 탭에서 도전하세요!'
                : '단기기억 단어가 없습니다.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ),
      );
    }
    return Card(
      child: Column(
        children: words.take(50).map((w) => _wordTile(store, w)).toList(),
      ),
    );
  }

  Widget _wordTile(WordStore store, WordEntry w) {
    return ListTile(
      dense: true,
      title: Text(w.word,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      subtitle: Text(
        [
          if (w.meaning.isNotEmpty) w.meaning.split('\n').first,
          DateFormat('yyyy/M/d').format(w.createdAt),
          if (w.tags.isNotEmpty) w.tags.map((t) => '#$t').join(' '),
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11),
      ),
      leading: IconButton(
        icon: const Icon(Icons.volume_up, color: AppTheme.teal, size: 20),
        onPressed: () => AudioService().pronounce(w.word, audioUrl: w.nativeAudioUrl),
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 20),
        onSelected: (action) async {
          switch (action) {
            case 'edit':
              await _editWordDialog(store, w);
              break;
            case 'move':
              w.stage = w.stage == 'long' ? 'short' : 'long';
              if (w.stage == 'short') w.correctStreak = 0;
              await store.updateWord(w);
              break;
            case 'delete':
              await _confirmDeleteWord(store, w);
              break;
          }
        },
        itemBuilder: (ctx) => [
          const PopupMenuItem(
              value: 'edit',
              child: ListTile(
                  leading: Icon(Icons.edit, size: 18),
                  title: Text('수정'),
                  dense: true)),
          PopupMenuItem(
              value: 'move',
              child: ListTile(
                  leading: Icon(
                      w.stage == 'long'
                          ? Icons.undo
                          : Icons.emoji_events,
                      size: 18),
                  title: Text(w.stage == 'long' ? '단기기억으로 이동' : '장기기억으로 이동'),
                  dense: true)),
          const PopupMenuItem(
              value: 'delete',
              child: ListTile(
                  leading: Icon(Icons.delete, size: 18, color: Colors.red),
                  title: Text('삭제', style: TextStyle(color: Colors.red)),
                  dense: true)),
        ],
      ),
    );
  }

  Future<void> _editWordDialog(WordStore store, WordEntry w) async {
    final wordCtrl = TextEditingController(text: w.word);
    final meaningCtrl = TextEditingController(text: w.meaning);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('단어 수정'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: wordCtrl,
                decoration: const InputDecoration(labelText: '단어')),
            const SizedBox(height: 12),
            TextField(
                controller: meaningCtrl,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(labelText: '뜻')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('저장')),
        ],
      ),
    );
    if (ok == true && wordCtrl.text.trim().isNotEmpty) {
      w.word = wordCtrl.text.trim();
      w.meaning = meaningCtrl.text.trim();
      await store.updateWord(w);
    }
  }

  Future<void> _confirmDeleteWord(WordStore store, WordEntry w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('"${w.word}" 삭제'),
        content: const Text('이 단어를 완전히 삭제할까요?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok == true) await store.deleteWord(w.id);
  }
}
