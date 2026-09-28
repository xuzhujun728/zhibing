import 'package:flutter/material.dart';

import 'backup_page.dart';

/// 全局汉堡菜单（抽屉）：病案列表、数据备份和还原。
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, this.current});

  /// 当前页面标识，用于避免重复导航。
  final String? current;

  void _goBackup(BuildContext context) {
    Navigator.pop(context); // 先关闭抽屉
    if (current == '/backup') return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BackupRestorePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: scheme.primary),
              child: const Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  '治病诊疗记录',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            _item(
              context,
              icon: Icons.list_alt_rounded,
              label: '病案列表',
              routeName: '/',
              onTap: () => Navigator.pop(context),
            ),
            _item(
              context,
              icon: Icons.settings_backup_restore_rounded,
              label: '数据备份和还原',
              routeName: '/backup',
              onTap: () => _goBackup(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String routeName,
    required VoidCallback onTap,
  }) {
    final selected = current == routeName;
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      selected: selected,
      onTap: onTap,
    );
  }
}
