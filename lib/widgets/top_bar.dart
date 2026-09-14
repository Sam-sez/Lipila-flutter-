import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/auth_provider.dart';
import '../theme/lipila_theme.dart';

class LipilaTopBar extends StatelessWidget implements PreferredSizeWidget {
  const LipilaTopBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return AppBar(
      automaticallyImplyLeading: false,
      title: const Text(
        'Lipila',
        style: TextStyle(color: LipilaColors.ember, fontWeight: FontWeight.w700, fontSize: 18),
      ),
      actions: [
        if (user != null)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: GestureDetector(
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Switch account?'),
                    content: const Text('You can log back in with your number anytime.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Switch')),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await context.read<AuthProvider>().logout();
                }
              },
              child: CircleAvatar(
                radius: 16,
                backgroundColor: LipilaColors.paperDim,
                child: Text(
                  user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '?',
                  style: const TextStyle(color: LipilaColors.espresso, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
