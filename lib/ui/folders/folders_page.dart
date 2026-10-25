import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../syncthing/controller.dart';
import '../../syncthing/models.dart';

import 'folder_edit_page.dart';
import 'folder_detail_page.dart';

/// 文件夹列表。
class FoldersPage extends StatelessWidget {
  const FoldersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SyncthingController>();
    final folders = ctrl.config?.folders ?? <FolderConfig>[];
    return Scaffold(
      appBar: AppBar(title: const Text('文件夹')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const FolderEditPage(folderId: null),
        )),
        icon: const Icon(Icons.add),
        label: const Text('添加文件夹'),
      ),
      body: ctrl.pendingFolders.isNotEmpty
          ? ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    '有 ${ctrl.pendingFolders.values.fold(0, (a, b) => a + b.length)} 个待接受的共享邀请（见「状态总览」）',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary),
                  ),
                ),
                ..._tiles(context, ctrl, folders),
                const SizedBox(height: 88),
              ],
            )
          : ListView(
              children: [..._tiles(context, ctrl, folders), const SizedBox(height: 88)]),
    );
  }

  List<Widget> _tiles(
      BuildContext context, SyncthingController ctrl, List<FolderConfig> folders) {
    if (folders.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('还没有同步文件夹，点击右下角添加')),
        ),
      ];
    }
    return [
      for (final f in folders)
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: Icon(
              switch (f.type) {
                'sendonly' => Icons.outbox_outlined,
                'receiveonly' => Icons.inbox_outlined,
                _ => Icons.sync_outlined,
              },
            ),
            title: Text(f.displayName),
            subtitle: Text(
              '${f.path}\n${typeLabel(f.type)} · 与 ${f.devices.length} 台设备共享',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            isThreeLine: true,
            trailing: f.paused
                ? const Icon(Icons.pause_circle_outline)
                : const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => FolderDetailPage(folderId: f.id),
            )),
          ),
        ),
    ];
  }
}

String typeLabel(String type) => switch (type) {
      'sendonly' => '仅发送',
      'receiveonly' => '仅接收',
      _ => '发送与接收',
    };
