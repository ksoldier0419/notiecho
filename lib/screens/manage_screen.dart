import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/word_entry.dart';
import '../services/word_store.dart';
import '../services/audio_service.dart';
import '../theme.dart';

/// 관리 탭: 통계 + 태그 관리 + 단계 수정 + 단어 목록 (태그/단계 필터)
class ManageScreen extends StatefulWidget {
  const ManageScreen({super.key});

  @override
  State<ManageScreen> createState() => _ManageScreenState();
}

class _ManageScreenState extends State<ManageScreen> {
  // 태그 필터: null = 전체
  List<String> _selectedTags = [];
  // 단계 필터: null = 전체
  String? _selectedStage;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<WordStore>();
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStats(store),
          const SizedBox(height: 16),
          _buildSectionHeader(Icons.label, '태그 관리'),
          _buildTagManager(store),
          const SizedBox(height: 16),
          _buildSectionHeader(Icons.tune, '단계 수정'),
          _buildStageReviewCard(store),
          const SizedBox(height: 16),
          _buildSectionHeader(Icons.filter_list, '단어 필터'),
          _buildFilterBar(store),
          const SizedBox(height: 8),
          _buildWordList(store),
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
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }

  // ─── 통계 ─────────────────────────────────────────────────
  Widget _buildStats(WordStore store) {
    final sc = store.stageCounts;
    return Card(
      color: AppTheme.deepIndigo,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statItem('전체', store.totalCount, Icons.library_books),
                _statItem('오늘', store.todayCount, Icons.today),
                _statItem('단기', store.shortTermCount, Icons.hourglass_bottom),
                _statItem('장기 🏆', store.longTermCount, Icons.emoji_events),
              ],
            ),
            const SizedBox(height: 12),
            // 단계별 미니 바
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: MemoryStage.all.map((s) {
                final cnt = sc[s] ?? 0;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${MemoryStage.getLabel(s)} $cnt',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 11),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statItem(String label, int value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: AppTheme.lightTeal, size: 20),
        const SizedBox(height: 4),
        Text('$value',
            style: const TextStyle(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }

  // ─── 태그 관리 ────────────────────────────────────────────
  Widget _buildTagManager(WordStore store) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 새 태그 만들기 버튼
            OutlinedButton.icon(
              onPressed: () => _createTagDialog(store),
              icon: const Icon(Icons.add, size: 16, color: AppTheme.teal),
              label: const Text('새 태그 만들기',
                  style: TextStyle(color: AppTheme.teal, fontSize: 13)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppTheme.teal),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
            if (store.tags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: store.tags.map((tag) {
                  final count =
                      store.words.where((w) => w.tags.contains(tag)).length;
                  return InputChip(
                    label: Text('$tag ($count)'),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => _confirmDeleteTag(store, tag),
                    onPressed: () => _renameTagDialog(store, tag),
                    tooltip: '탭: 이름 수정',
                  );
                }).toList(),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text('태그가 없습니다. 위 버튼으로 태그를 만들어보세요.',
                  style: TextStyle(
                      color: Colors.grey.shade500, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _createTagDialog(WordStore store) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('새 태그 만들기'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              hintText: '태그 이름 (예: Biology, TOEIC)'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('만들기')),
        ],
      ),
    );
    final tag = result?.trim() ?? '';
    if (tag.isNotEmpty) await store.addTag(tag);
  }

  Future<void> _renameTagDialog(WordStore store, String tag) async {
    final ctrl = TextEditingController(text: tag);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('태그 이름 수정'),
        content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(hintText: '새 태그 이름')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소')),
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

  // ─── 단계 수정 ────────────────────────────────────────────
  Widget _buildStageReviewCard(WordStore store) {
    // 초과 단어 미리 계산
    final overdueCount = store.words.where((w) => w.isOverdue).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  overdueCount > 0
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline,
                  color: overdueCount > 0
                      ? Colors.orange
                      : Colors.green,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    overdueCount > 0
                        ? '복습 주기 초과 단어 $overdueCount개 발견'
                        : '모든 단어가 복습 주기 내에 있습니다',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '주기 초과 단어를 한 단계 강등하고 날짜를 오늘로 갱신합니다.\n'
              '예) 단기5 → 단기3, stageDate = 오늘',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: overdueCount == 0
                    ? null
                    : () => _runStageReview(store),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(
                  overdueCount > 0
                      ? '단계 수정 실행 ($overdueCount개)'
                      : '수정 대상 없음',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: overdueCount > 0
                      ? Colors.orange
                      : Colors.grey.shade300,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runStageReview(WordStore store) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('단계 수정 실행'),
        content: const Text(
          '복습 주기를 초과한 단어를 한 단계 강등하고\n'
          'stageDate를 오늘로 갱신합니다.\n\n계속할까요?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('실행'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final count = await store.reviewAndDemoteOverdue();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$count개 단어의 단계가 조정되었습니다.'),
        backgroundColor: AppTheme.teal,
      ),
    );
  }

  // ─── 필터 바 ──────────────────────────────────────────────
  Widget _buildFilterBar(WordStore store) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 태그 필터
            if (store.tags.isNotEmpty) ...[
              Text('태그',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  FilterChip(
                    label: const Text('전체', style: TextStyle(fontSize: 12)),
                    selected: _selectedTags.isEmpty,
                    selectedColor: AppTheme.lightTeal,
                    onSelected: (_) =>
                        setState(() => _selectedTags = []),
                  ),
                  ...store.tags.map((tag) => FilterChip(
                        label: Text(tag, style: const TextStyle(fontSize: 12)),
                        selected: _selectedTags.contains(tag),
                        selectedColor: AppTheme.lightTeal,
                        checkmarkColor: AppTheme.deepIndigo,
                        onSelected: (v) {
                          setState(() {
                            if (v) {
                              _selectedTags = [..._selectedTags, tag];
                            } else {
                              _selectedTags =
                                  _selectedTags.where((t) => t != tag).toList();
                            }
                          });
                        },
                      )),
                ],
              ),
              const SizedBox(height: 12),
            ],
            // 단계 필터
            Text('단계',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                FilterChip(
                  label: const Text('전체', style: TextStyle(fontSize: 12)),
                  selected: _selectedStage == null,
                  selectedColor: AppTheme.lightTeal,
                  onSelected: (_) =>
                      setState(() => _selectedStage = null),
                ),
                ...MemoryStage.all.map((s) => FilterChip(
                      label: Text(MemoryStage.getLabel(s),
                          style: const TextStyle(fontSize: 12)),
                      selected: _selectedStage == s,
                      selectedColor: _stageColor(s).withValues(alpha: 0.2),
                      checkmarkColor: _stageColor(s),
                      side: BorderSide(
                          color: _selectedStage == s
                              ? _stageColor(s)
                              : Colors.grey.shade300),
                      onSelected: (_) =>
                          setState(() => _selectedStage = s),
                    )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _stageColor(String stage) {
    if (stage.startsWith('long')) return Colors.purple.shade600;
    switch (stage) {
      case 'short3':  return Colors.red.shade500;
      case 'short5':  return Colors.orange.shade600;
      case 'short10': return Colors.amber.shade700;
      case 'short15': return Colors.green.shade600;
      default:        return Colors.grey;
    }
  }

  // ─── 단어 목록 ────────────────────────────────────────────
  Widget _buildWordList(WordStore store) {
    final words = store.filter(
      tags: _selectedTags.isEmpty ? null : _selectedTags,
      stage: _selectedStage,
    );

    if (words.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '해당 조건의 단어가 없습니다.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ),
      );
    }

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text('${words.length}개',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w600)),
          ),
          ...words.take(100).map((w) => _wordTile(store, w)),
        ],
      ),
    );
  }

  Widget _wordTile(WordStore store, WordEntry w) {
    final stageColor = _stageColor(w.stage);
    final dateStr = DateFormat('yy/M/d').format(w.stageDate);
    final overdue = w.isOverdue;

    return ListTile(
      dense: true,
      title: Row(
        children: [
          Text(w.word,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(width: 8),
          // 단계 뱃지
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: stageColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: stageColor.withValues(alpha: 0.4)),
            ),
            child: Text(
              w.stageLabel,
              style: TextStyle(
                  fontSize: 10,
                  color: stageColor,
                  fontWeight: FontWeight.bold),
            ),
          ),
          if (overdue) ...[
            const SizedBox(width: 4),
            Icon(Icons.warning_amber_rounded,
                size: 14, color: Colors.orange.shade600),
          ],
        ],
      ),
      subtitle: Text(
        [
          if (w.meaning.isNotEmpty) w.meaning.split('\n').first,
          '단계진입: $dateStr',
          if (w.tags.isNotEmpty) w.tags.map((t) => '#$t').join(' '),
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11),
      ),
      leading: IconButton(
        icon: const Icon(Icons.volume_up, color: AppTheme.teal, size: 20),
        onPressed: () =>
            AudioService().pronounce(w.word, audioUrl: w.nativeAudioUrl),
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 20),
        onSelected: (action) async {
          switch (action) {
            case 'edit':
              await _editWordDialog(store, w);
              break;
            case 'promote':
              await store.promoteStage(w);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        Text('"${w.word}" → ${w.stageLabel}'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
              break;
            case 'demote':
              await store.demoteStage(w);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        Text('"${w.word}" → ${w.stageLabel}'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
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
              value: 'promote',
              child: ListTile(
                  leading: const Icon(Icons.arrow_upward,
                      size: 18, color: Colors.green),
                  title: Text(
                      '승급 → ${MemoryStage.getLabel(MemoryStage.promote(w.stage))}'),
                  dense: true)),
          PopupMenuItem(
              value: 'demote',
              child: ListTile(
                  leading: const Icon(Icons.arrow_downward,
                      size: 18, color: Colors.orange),
                  title: Text(
                      '강등 → ${MemoryStage.getLabel(MemoryStage.demote(w.stage))}'),
                  dense: true)),
          const PopupMenuItem(
              value: 'delete',
              child: ListTile(
                  leading:
                      Icon(Icons.delete, size: 18, color: Colors.red),
                  title: Text('삭제',
                      style: TextStyle(color: Colors.red)),
                  dense: true)),
        ],
      ),
    );
  }

  // ─── 단어 수정 다이얼로그 ─────────────────────────────────
  Future<void> _editWordDialog(WordStore store, WordEntry w) async {
    final wordCtrl = TextEditingController(text: w.word);
    final meaningCtrl = TextEditingController(text: w.meaning);
    final selectedTags = Set<String>.from(w.tags);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('단어 수정'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                    controller: wordCtrl,
                    decoration:
                        const InputDecoration(labelText: '단어')),
                const SizedBox(height: 12),
                TextField(
                    controller: meaningCtrl,
                    maxLines: 3,
                    minLines: 1,
                    decoration:
                        const InputDecoration(labelText: '뜻')),
                const SizedBox(height: 16),
                const Text('태그',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (store.tags.isEmpty)
                  Text('태그 없음',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500))
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: store.tags.map((tag) {
                      final isSel = selectedTags.contains(tag);
                      return FilterChip(
                        label: Text(tag,
                            style:
                                const TextStyle(fontSize: 12)),
                        selected: isSel,
                        selectedColor: AppTheme.lightTeal,
                        checkmarkColor: AppTheme.deepIndigo,
                        visualDensity: VisualDensity.compact,
                        onSelected: (v) {
                          setDialogState(() {
                            if (v) {
                              selectedTags.add(tag);
                            } else {
                              selectedTags.remove(tag);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
              ],
            ),
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
      ),
    );
    if (ok == true && wordCtrl.text.trim().isNotEmpty) {
      w.word = wordCtrl.text.trim();
      w.meaning = meaningCtrl.text.trim();
      w.tags = selectedTags.toList();
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
