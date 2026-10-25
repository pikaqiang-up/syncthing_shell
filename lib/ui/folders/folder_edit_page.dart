import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/native_bridge.dart';
import '../../syncthing/controller.dart';
import '../../syncthing/models.dart';
import '../widgets/common.dart';

/// 文件夹添加 / 编辑（覆盖 web 前端文件夹弹窗的全部字段）。
class FolderEditPage extends StatefulWidget {
  const FolderEditPage({super.key, this.folderId});

  final String? folderId;

  @override
  State<FolderEditPage> createState() => _FolderEditPageState();
}

class _FolderEditPageState extends State<FolderEditPage> {
  late FolderConfig folder;
  bool get isNew => widget.folderId == null;
  bool _loaded = false;
  bool _saving = false;

  /// 程序化赋值后需要刷新显示的字段（目录选择器回填路径）必须用
  /// controller 管理——initialValue 只在首次 build 生效。
  final _labelCtl = TextEditingController();
  final _idCtl = TextEditingController();
  final _pathCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final ctrl = context.read<SyncthingController>();
    final existing = widget.folderId == null ? null : ctrl.config?.folder(widget.folderId!);
    if (existing != null) {
      folder = existing;
      _labelCtl.text = folder.label;
      _idCtl.text = folder.id;
      _pathCtl.text = folder.path;
      _loaded = true;
    } else {
      // 用 syncthing 自带的默认模板，升级后字段自动跟随
      ctrl.folderTemplate().then((t) {
        if (mounted) {
          setState(() {
            t['id'] = '';
            t['label'] = '';
            t['path'] = '';
            t['devices'] = [];
            folder = FolderConfig(t);
            _loaded = true;
          });
        }
      });
    }
  }

  Future<void> _save() async {
    if (folder.id.trim().isEmpty) {
      showSnack(context, '文件夹 ID 不能为空', error: true);
      return;
    }
    if (folder.path.trim().isEmpty) {
      showSnack(context, '路径不能为空', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      // 确保自己也在 devices 里
      final devices = folder.devices.where((d) => d.deviceID != ctrl.myID).toList()
        ..insert(0, FolderDeviceRef(deviceID: ctrl.myID));
      folder.devices = devices;
      await ctrl.saveFolder(folder);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showSnack(context, '保存失败: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  SyncthingController get ctrl => context.read<SyncthingController>();

  @override
  void dispose() {
    _labelCtl.dispose();
    _idCtl.dispose();
    _pathCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? '添加文件夹' : '编辑文件夹'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('保存'),
          ),
        ],
      ),
      body: _loaded
          ? ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _Section('常规'),
                ListTile(
                  title: TextFormField(
                    controller: _labelCtl,
                    decoration: const InputDecoration(
                        labelText: '文件夹标签（显示名）',
                        border: OutlineInputBorder()),
                    onChanged: (v) {
                      folder.label = v;
                      if (isNew && _idCtl.text.isEmpty) {
                        final generated =
                            v.trim().replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '-');
                        _idCtl.text = generated;
                        folder.id = generated;
                      }
                    },
                  ),
                ),
                if (isNew)
                  ListTile(
                    title: TextFormField(
                      controller: _idCtl,
                      decoration: const InputDecoration(
                          labelText: '文件夹 ID（与其他设备一致）',
                          border: OutlineInputBorder()),
                      onChanged: (v) => folder.id = v.trim(),
                    ),
                  ),
                ListTile(
                  title: TextFormField(
                    controller: _pathCtl,
                    enabled: isNew,
                    decoration: InputDecoration(
                      labelText: '存储路径',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.folder_open),
                        onPressed: isNew ? () => _pickPath() : null,
                      ),
                    ),
                    onChanged: (v) => folder.path = v,
                  ),
                  subtitle: isNew
                      ? const Text('建议通过系统选择器选择，也可手动输入')
                      : null,
                ),
                if (isNew)
                  ListTile(
                    title: const Text('文件夹类型'),
                    subtitle: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'sendreceive', label: Text('双向')),
                        ButtonSegment(value: 'sendonly', label: Text('仅发送')),
                        ButtonSegment(value: 'receiveonly', label: Text('仅接收')),
                      ],
                      selected: {folder.type},
                      onSelectionChanged: (s) =>
                          setState(() => folder.type = s.first),
                    ),
                  ),
                SwitchListTile(
                  title: const Text('暂停此文件夹'),
                  value: folder.paused,
                  onChanged: (v) => setState(() => folder.paused = v),
                ),
                _Section('共享'),
                for (final d in ctrl.config?.devices ?? <DeviceConfig>[])
                  if (d.deviceID != ctrl.myID)
                    CheckboxListTile(
                      value: folder.deviceShared(d.deviceID),
                      title: Text(d.displayName),
                      subtitle: Text(formatDeviceIdShort(d.deviceID)),
                      onChanged: (v) {
                        final devices = folder.devices
                            .where((x) => x.deviceID != d.deviceID)
                            .toList();
                        if (v == true) {
                          devices.add(FolderDeviceRef(deviceID: d.deviceID));
                        }
                        setState(() => folder.devices = devices);
                      },
                    ),
                _Section('扫描'),
                ListTile(
                  title: TextFormField(
                    initialValue: folder.rescanIntervalS.toString(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: '完全重新扫描间隔（秒）',
                        border: OutlineInputBorder()),
                    onChanged: (v) =>
                        folder.rescanIntervalS = int.tryParse(v) ?? 3600,
                  ),
                ),
                SwitchListTile(
                  title: const Text('监视文件系统变化'),
                  subtitle: const Text('实时响应文件改动（推荐开启）'),
                  value: folder.fsWatcherEnabled,
                  onChanged: (v) => setState(() => folder.fsWatcherEnabled = v),
                ),
                SwitchListTile(
                  title: const Text('忽略文件权限'),
                  subtitle: const Text('文件系统不支持权限时使用（如 FAT/exFAT）'),
                  value: folder.ignorePerms,
                  onChanged: (v) => setState(() => folder.ignorePerms = v),
                ),
                _Section('版本控制（文件回收）'),
                _VersioningEditor(
                  versioning: folder.versioning,
                  onChanged: () => setState(() {}),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Future<void> _pickPath() async {
    final path = await NativeBridge.instance.pickDirectory();
    if (path != null) {
      // controller 回填让路径立即可见（initialValue 不会刷新）
      setState(() {
        _pathCtl.text = path;
        folder.path = path;
      });
    }
  }
}

Future<void> showSnack2() async {}

String formatDeviceIdShort(String id) => id.length > 14
    ? '${id.substring(0, 7)}…${id.substring(id.length - 7)}'
    : id;

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Text(title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary)),
    );
  }
}

class _VersioningEditor extends StatelessWidget {
  const _VersioningEditor({required this.versioning, required this.onChanged});

  final VersioningConfig versioning;
  final VoidCallback onChanged;

  static const _types = [
    ('', '不保留版本'),
    ('trashcan', '回收站（定期清理）'),
    ('simple', '简单（保留 N 份）'),
    ('snapshot', '快照（每次扫描一份）'),
    ('staggered', '交错（按时间梯度）'),
    ('external', '外部命令'),
  ];

  @override
  Widget build(BuildContext context) {
    final params = versioning.params;
    return Column(children: [
      for (final (t, label) in _types)
        RadioListTile<String>(
          value: t,
          groupValue: versioning.type,
          title: Text(label),
          onChanged: (v) {
            versioning.type = v ?? '';
            versioning.params = defaultParams(v ?? '');
            onChanged();
          },
        ),
      if (versioning.type == 'trashcan')
        _ParamField(
          label: '保留天数 (cleanoutDays)',
          value: params['cleanoutDays'] ?? '0',
          onChanged: (v) => params['cleanoutDays'] = v,
        ),
      if (versioning.type == 'simple')
        _ParamField(
          label: '保留份数 (keep)',
          value: params['keep'] ?? '5',
          onChanged: (v) => params['keep'] = v,
        ),
      if (versioning.type == 'simple')
        _ParamField(
          label: '清理间隔秒 (cleanInterval)',
          value: params['cleanInterval'] ?? '3600',
          onChanged: (v) => params['cleanInterval'] = v,
        ),
      if (versioning.type == 'snapshot')
        _ParamField(
          label: '保留路径份数 (keep)',
          value: params['keep'] ?? '5',
          onChanged: (v) => params['keep'] = v,
        ),
      if (versioning.type == 'staggered') ...[
        _ParamField(
          label: '最大保留秒 (maxAge)',
          value: params['maxAge'] ?? '31536000',
          onChanged: (v) => params['maxAge'] = v,
        ),
        _ParamField(
          label: '清理间隔秒 (cleanInterval)',
          value: params['cleanInterval'] ?? '3600',
          onChanged: (v) => params['cleanInterval'] = v,
        ),
      ],
      if (versioning.type == 'external')
        _ParamField(
          label: '命令 (command)',
          value: params['command'] ?? '',
          onChanged: (v) => params['command'] = v,
        ),
    ]);
  }

  Map<String, String> defaultParams(String type) => switch (type) {
        'trashcan' => {'cleanoutDays': '0'},
        'simple' => {'keep': '5', 'cleanInterval': '3600'},
        'snapshot' => {'keep': '5'},
        'staggered' => {'maxAge': '31536000', 'cleanInterval': '3600'},
        'external' => {'command': ''},
        _ => <String, String>{},
      };
}

class _ParamField extends StatelessWidget {
  const _ParamField(
      {required this.label, required this.value, required this.onChanged});

  final String label;
  final String value;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextFormField(
        initialValue: value,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        onChanged: onChanged,
      ),
    );
  }
}
