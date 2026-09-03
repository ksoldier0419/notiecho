import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/word_store.dart';
import 'services/audio_service.dart';
import 'theme.dart';
import 'screens/record_screen.dart';
import 'screens/play_screen.dart';
import 'screens/test_screen.dart';
import 'screens/manage_screen.dart';

/// 앱 버전 — pubspec.yaml 버전과 동기화해서 관리
const String kAppVersion = '1.1.0';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = WordStore();
  await store.init();
  await AudioService().init();

  runApp(NotiEchoApp(store: store));
}

class NotiEchoApp extends StatelessWidget {
  final WordStore store;
  const NotiEchoApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        title: 'NotiEcho',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const HomeShell(),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _tabTitles = ['녹음', '플레이', '시험', '관리'];

  @override
  Widget build(BuildContext context) {
    final screens = const [
      RecordScreen(),
      PlayScreen(),
      TestScreen(),
      ManageScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.graphic_eq, size: 20),
            const SizedBox(width: 7),
            const Text(
              'NotiEcho',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
            const SizedBox(width: 6),
            // 버전 표시
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'v$kAppVersion',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
        // 현재 탭 이름을 우측에 작게 표시
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                _tabTitles[_index],
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.75),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(child: IndexedStack(index: _index, children: screens)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          AudioService().stopAll();
          setState(() => _index = i);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.mic_none), selectedIcon: Icon(Icons.mic), label: '녹음'),
          NavigationDestination(icon: Icon(Icons.play_circle_outline), selectedIcon: Icon(Icons.play_circle), label: '플레이'),
          NavigationDestination(icon: Icon(Icons.quiz_outlined), selectedIcon: Icon(Icons.quiz), label: '시험'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: '관리'),
        ],
      ),
    );
  }
}
