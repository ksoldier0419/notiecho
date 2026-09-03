import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/word_store.dart';
import 'services/audio_service.dart';
import 'theme.dart';
import 'screens/record_screen.dart';
import 'screens/play_screen.dart';
import 'screens/test_screen.dart';
import 'screens/manage_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    final screens = const [
      RecordScreen(),
      PlayScreen(),
      TestScreen(),
      ManageScreen(),
    ];

    return Scaffold(
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
