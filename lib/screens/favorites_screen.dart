import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/auth_provider.dart';
import '../api/favorites_api.dart';
import '../models/display_identity.dart';
import '../theme/lipila_theme.dart';
import '../widgets/pay_confirm_sheet.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final _favoritesApi = FavoritesApi();
  List<DisplayIdentity> _favorites = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = context.read<AuthProvider>().user!.id;
    final favs = await _favoritesApi.list(userId);
    setState(() { _favorites = favs; _loading = false; });
  }

  Future<void> _remove(String savedUserId) async {
    final userId = context.read<AuthProvider>().user!.id;
    await _favoritesApi.remove(userId, savedUserId);
    setState(() => _favorites.removeWhere((f) => f.userId == savedUserId));
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.read<AuthProvider>().user!.id;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_favorites.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "No favorites yet. After your next payment, Lipila will ask if you'd like to save that person.",
            textAlign: TextAlign.center, style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _favorites.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: LipilaColors.line),
      itemBuilder: (ctx, i) {
        final f = _favorites[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: LipilaColors.paperDim,
            child: Text(f.name.isNotEmpty ? f.name[0].toUpperCase() : '?'),
          ),
          title: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('✓ ···${f.verifiedNumberSuffix}', style: const TextStyle(color: LipilaColors.success, fontSize: 12)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton(
              onPressed: () => showPayConfirmSheet(context: context, payerId: userId, payee: f, method: 'favorite'),
              child: const Text('Pay'),
            ),
            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => _remove(f.userId)),
          ]),
        );
      },
    );
  }
}
