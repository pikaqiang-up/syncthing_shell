import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';

import '../../syncthing/controller.dart';
import '../../syncthing/models.dart';
import '../widgets/common.dart';
import 'folder_browse_page.dart';
import 'folder_edit_page.dart';
import 'folder_versions_page.dart';
import 'ignore_patterns_page.dart';

/// 文件夹详情：状态、统计、各设备完成度、失败项、动作、入口（编辑/忽略/浏览/版本）。
class FolderDetailPage extends StatelessWidget {
  FolderDetailPage({super.key, required this.folderId});

  final String folderId;

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SyncthingController>();
    final folder = ctrl.config?.folder(folderId);
    if (folder == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('文件夹')),
        body: const Center(child: Text('文件夹不存在')),
      );
    }
    final status = ctrl.folderStatuses[folderId];
    final view = FolderStateView.of(context, folder, status, ctrl);
    return Scaffold(
      appBar: AppBar(
        title: Text(folder.displayName),
        actions: [
          PopupMenuButton<String>(
            onSelected: (a) => _onAction(context, ctrl, folder, a),
            itemBuilder: (_) {
              final hasLocalChanges =
                  (status?.receiveOnlyTotalItems ?? 0) > 0;
              final canOverride = folder.type == 'sendonly' ||
                  (folder.type == 'receiveonly' && hasLocalChanges);
              final canRevert =
                  folder.type == 'receiveonly' && hasLocalChanges;
              return [
                const PopupMenuItem(value: 'rescan', child: Text('重新扫描')),
                if (canOverride)
                  const PopupMenuItem(
                      value: 'override', child: Text('以本机为准覆盖')),
                if (canRevert)
                  const PopupMenuItem(
                      value: 'revert', child: Text('放弃本地更改')),
                PopupMenuItem(
                  value: 'pause',
                  child: Text(folder.paused ? '恢复' : '暂停'),
                ),
                const PopupMenuItem(value: 'edit', child: Text('编辑')),
                const PopupMenuItem(value: 'delete', child: Text('删除')),
              ];
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(view.text,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: view.color)),
                    const Spacer(),
                    if (status?.state == 'syncing' && status != null)
                      Text('${formatPercent(status.completion)}'),
                  ]),
                  const SizedBox(height: 4),
                  Text(folder.path, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  if (status != null)
                    LinearProgressIndicator(
                      value: status.state == 'syncing'
                          ? status.completion / 100
                          : (status.state == 'scanning' &&
                                  status.scanPercentage != null
                              ? status.scanPercentage! / 100
                              : null),
                      minHeight: 6,
                    ),
                  if (status?.stateChanged != null) ...[
                    const SizedBox(height: 8),
                    Text('状态更新于 ${formatTime(status!.stateChanged)}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ),
          _StatsSection(ctrl: ctrl, folder: folder, status: status),
          _CompletionSection(ctrl: ctrl, folder: folder),
          _ErrorsSection(ctrl: ctrl, folderId: folderId),
          _EntrySection(ctrl: ctrl, folder: folder),
        ],
      ),
    );
  }

  Future<void> _onAction(BuildContext context, SyncthingController ctrl,
      FolderConfig folder, String action) async {
    switch (action) {
      case 'rescan':
        await ctrl.rescanFolder(folder.id);
      case 'override':
        if (await confirmDialog(context,
            title: '覆盖远程更改',
            message: '以本机内容为准，把差异推送到其他设备？')) {
          await ctrl.overrideFolder(folder.id);
        }
      case 'revert':
        if (await confirmDialog(context,
            title: '放弃本地更改',
            message: '把本地改动回退为远程版本？此操作不可撤销。')) {
          await ctrl.revertFolder(folder.id);
        }
      case 'pause':
        await ctrl.pauseFolder(folder.id, !folder.paused);
      case 'edit':
        if (context.mounted) {
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => FolderEditPage(folderId: folder.id)));
        }
      case 'delete':
        if (await confirmDialog(context,
            title: '删除文件夹',
            message: '从 Syncthing 移除「${folder.displayName}」？磁盘文件不会被删除。',
            destructive: true)) {
          await ctrl.deleteFolder(folder.id);
          if (context.mounted) Navigator.of(context).pop();
        }
    }
  }
}

class _StatsSection extends StatelessWidget {
  const _StatsSection({required this.ctrl, required this.folder, this.status});

  final SyncthingController ctrl;
  final FolderConfig folder;
  final FolderStatus? status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (s == null) return const SizedBox.shrink();
    Widget row(String label, String global, String local, String outOfSync) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(children: [
            Expanded(child: Text(label)),
            SizedBox(
                width: 90,
                child: Text(global, textAlign: TextAlign.end, style: const TextStyle(fontSize: 13))),
            SizedBox(
                width: 90,
                child: Text(local, textAlign: TextAlign.end, style: const TextStyle(fontSize: 13))),
            SizedBox(
                width: 80,
                child: Text(outOfSync, textAlign: TextAlign.end, style: const TextStyle(fontSize: 13))),
          ]),
        );
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              const Expanded(child: Text('')),
              SizedBox(
                  width: 90,
                  child: Text('全局',
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.labelSmall)),
              SizedBox(
                  width: 90,
                  child: Text('本机',
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.labelSmall)),
              SizedBox(
                  width: 80,
                  child: Text('待同步',
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.labelSmall)),
            ]),
          ),
          row('文件', '${s.globalFiles}', '${s.localFiles}', '${s.needFiles}'),
          row('目录', '${s.globalDirectories}', '${s.localDirectories}', '${s.needDirectories}'),
          row('大小', formatBytes(s.globalBytes), formatBytes(s.localBytes), formatBytes(s.needBytes)),
          row('已删除', '${s.globalDeleted}', '${s.localDeleted}', '${s.needDeletes}'),
        ]),
      ),
    );
  }
}

class _CompletionSection extends StatelessWidget {
  const _CompletionSection({required this.ctrl, required this.folder});

  final SyncthingController ctrl;
  final FolderConfig folder;

  @override
  Widget build(BuildContext context) {
    final perDevice = ctrl.completions[folder.id];
    if (perDevice == null || perDevice.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (final e in perDevice.entries)
            ListTile(
              dense: true,
              title: Text(ctrl.config?.device(e.key)?.displayName ?? formatDeviceId(e.key)),
              trailing: Text(
                e.value.completion >= 100
                    ? '最新'
                    : '${formatPercent(e.value.completion)} · 差 ${formatBytes(e.value.needBytes)}',
                style: TextStyle(
                  color: e.value.completion >= 100 ? Colors.green : Colors.orange,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorsSection extends StatelessWidget {
  const _ErrorsSection({required this.ctrl, required this.folderId});

  final SyncthingController ctrl;
  final String folderId;

  @override
  Widget build(BuildContext context) {
    final status = ctrl.folderStatuses[folderId];
    if ((status?.pullErrors ?? 0) == 0) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
            title: Text('${status?.pullErrors} 个失败项目'),
            subtitle: const Text('点按查看详情'),
            onTap: () => ctrl.refreshFolderErrors(folderId),
          ),
          for (final e in ctrl.folderErrors[folderId] ?? const <FolderErrorEntry>[])
            ListTile(
              dense: true,
              title: Text(e.path,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
              subtitle: Text(e.error,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
  }
}

class _EntrySection extends StatelessWidget {
  const _EntrySection({required this.ctrl, required this.folder});

  final SyncthingController ctrl;
  final FolderConfig folder;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('浏览文件'),
            subtitle: const Text('查看文件夹内容与本地/全局状态'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => FolderBrowsePage(folderId: folder.id))),
          ),
          ListTile(
            leading: const Icon(Icons.block),
            title: const Text('忽略模式'),
            subtitle: const Text('排除不需要同步的文件'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => IgnorePatternsPage(folderId: folder.id))),
          ),
          if (folder.versioning.enabled)
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('文件版本'),
              subtitle: Text('版本控制：${versioningLabel(folder.versioning.type)}'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => FolderVersionsPage(folderId: folder.id))),
            ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('编辑配置'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => FolderEditPage(folderId: folder.id))),
          ),
        ],
      ),
    );
  }
}

String versioningLabel(String type) => switch (type) {
      'trashcan' => '回收站',
      'simple' => '简单版本控制',
      'snapshot' => '快照版本控制',
      'staggered' => '交错版本控制',
      'external' => '外部命令',
      _ => type,
    };
