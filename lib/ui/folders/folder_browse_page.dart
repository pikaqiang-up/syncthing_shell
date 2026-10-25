import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../syncthing/controller.dart';
import '../../syncthing/models.dart';

/// 文件夹内文件浏览（/rest/db/browse）：名称/大小/修改时间/本地状态。
class FolderBrowsePage extends StatefulWidget {
  const FolderBrowsePage({super.key, required this.folderId, this.prefix = ''});

  final String folderId;
  final String prefix;

  @override
  State<FolderBrowsePage> createState() => _FolderBrowsePageState();
}

class _FolderBrowsePageState extends State<FolderBrowsePage> {
  List<BrowseEntry>? _entries;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _entries = null;
      _error = null;
    });
    try {
      final entries = await context.read<SyncthingController>().browse(
            widget.folderId,
            widget.prefix,
          );
      entries.sort((a, b) {
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      setState(() => _entries = entries);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = context.read<SyncthingController>().config?.folder(widget.folderId)?.displayName;
    return Scaffold(
      appBar: AppBar(title: Text(widget.prefix.isEmpty ? (label ?? '浏览') : widget.prefix.split('/').last)),
      body: _error != null
          ? Center(child: Text('加载失败: $_error'))
          : _entries == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: _entries!.length,
                    itemBuilder: (_, i) {
                      final e = _entries![i];
                      final path = widget.prefix.isEmpty
                          ? e.name
                          : '${widget.prefix}/${e.name}';
                      return ListTile(
                        leading: Icon(e.isDir ? Icons.folder : Icons.insert_drive_file),
                        title: Text(e.name),
                        subtitle: e.isDir
                            ? null
                            : Text(formatBytes(e.size), style: const TextStyle(fontSize: 12)),
                        trailing: e.modTime != null
                            ? Text(formatTime(e.modTime),
                                style: const TextStyle(fontSize: 11))
                            : null,
                        onTap: e.isDir
                            ? () => Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => FolderBrowsePage(
                                      folderId: widget.folderId, prefix: path),
                                ))
                            : null,
                      );
                    },
                  ),
                ),
    );
  }
}
