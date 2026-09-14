import 'package:flutter/material.dart';
import '../widgets/top_bar.dart';
import 'home_screen.dart';
import 'history_screen.dart';
import 'favorites_screen.dart';

/// Bottom-nav shell for the three "always reachable" screens. Scan,
/// Request, Bong, and Agent Tools are pushed as full routes from Home's
/// Quick Actions instead, matching the web app's structure.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _screens = [
    HomeScreen(),
    HistoryScreen(),
    FavoritesScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const LipilaTopBar(),
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'History'),
          NavigationDestination(icon: Icon(Icons.star_outline), selectedIcon: Icon(Icons.star), label: 'Favorites'),
        ],
      ),
    );
  }
}
