import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../syncthing/controller.dart';
import '../../syncthing/models.dart';
import '../widgets/common.dart';

/// 文件版本恢复（/rest/folder/versions + POST 恢复）。
class FolderVersionsPage extends StatefulWidget {
  const FolderVersionsPage({super.key, required this.folderId});

  final String folderId;

  @override
  State<FolderVersionsPage> createState() => _FolderVersionsPageState();
}

class _FolderVersionsPageState extends State<FolderVersionsPage> {
  Map<String, List<FileVersion>>? _versions;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await context.read<SyncthingController>().folderVersions(widget.folderId);
      setState(() => _versions = v);
    } catch (e) {
      setState(() => _versions = {});
    }
  }

  Future<void> _restore(String path, int versionTime) async {
    final ctrl = context.read<SyncthingController>();
    try {
      await ctrl.restoreVersions(widget.folderId, {path: versionTime});
      if (mounted) showSnack(context, '已提交恢复请求: $path');
    } catch (e) {
      if (mounted) showSnack(context, '恢复失败: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final versions = _versions;
    return Scaffold(
      appBar: AppBar(title: const Text('文件版本')),
      body: versions == null
          ? const Center(child: CircularProgressIndicator())
          : versions.isEmpty
              ? const Center(child: Text('没有可恢复的历史版本'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    children: [
                      for (final e in versions.entries)
                        ExpansionTile(
                          leading: const Icon(Icons.history),
                          title: Text(e.key,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${e.value.length} 个版本'),
                          children: [
                            for (final v in e.value)
                              ListTile(
                                dense: true,
                                title: Text(
                                  v.deleted
                                      ? '(已删除副本)'
                                      : formatBytes(v.size),
                                  style: const TextStyle(fontSize: 13),
                                ),
                                subtitle: Text(
                                  '版本时间 ${formatTime(DateTime.fromMillisecondsSinceEpoch(v.versionTime * 1000))}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                trailing: TextButton(
                                  onPressed: () => _restore(e.key, v.versionTime),
                                  child: const Text('恢复'),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
    );
  }
}
