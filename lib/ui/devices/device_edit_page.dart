import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../syncthing/controller.dart';
import '../../syncthing/models.dart';
import '../widgets/common.dart';
import 'device_scanner_page.dart';

/// 设备添加 / 编辑（覆盖 web 前端设备弹窗字段）。
class DeviceEditPage extends StatefulWidget {
  const DeviceEditPage({super.key, this.deviceID});

  final String? deviceID;

  @override
  State<DeviceEditPage> createState() => _DeviceEditPageState();
}

class _DeviceEditPageState extends State<DeviceEditPage> {
  late DeviceConfig device;
  bool get isNew => widget.deviceID == null;
  bool _saving = false;
  String? _idError;

  /// 设备 ID 输入框：程序化赋值（扫码/粘贴）后需要立即刷新显示，
  /// initialValue 只在首次 build 生效，故必须用 controller。
  final _idCtl = TextEditingController();

  SyncthingController get ctrl => context.read<SyncthingController>();

  @override
  void initState() {
    super.initState();
    final existing =
        widget.deviceID == null ? null : ctrl.config?.device(widget.deviceID!);
    if (existing != null) {
      device = existing;
      _idCtl.text = device.deviceID;
    } else {
      // 用 syncthing 自带默认模板，升级后字段自动跟随
      device = DeviceConfig.create('');
      ctrl.deviceTemplate().then((t) {
        if (mounted) {
          setState(() {
            t['deviceID'] = '';
            t['name'] = '';
            t['addresses'] = ['dynamic'];
            device = DeviceConfig(t);
          });
        }
      });
    }
  }

  Future<bool> _validateId() async {
    if (device.deviceID.trim().isEmpty) {
      setState(() => _idError = '设备 ID 不能为空');
      return false;
    }
    setState(() => _idError = null);
    try {
      final normalized = await ctrl.validateDeviceId(device.deviceID.trim());
      device.raw['deviceID'] = normalized;
      return true;
    } catch (e) {
      setState(() => _idError = '无效的设备 ID');
      return false;
    }
  }

  Future<void> _save() async {
    if (isNew && !await _validateId()) return;
    setState(() => _saving = true);
    try {
      await ctrl.saveDevice(device);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showSnack(context, '保存失败: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _idCtl.dispose();
    super.dispose();
  }

  /// 写入设备 ID 并同步输入框显示。
  void _setId(String value) {
    _idCtl.text = value.trim();
    device.raw['deviceID'] = value.trim();
  }

  /// 打开扫码页识别设备 ID。
  Future<void> _scanId() async {
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const DeviceIdScannerPage()),
    );
    if (value == null || value.trim().isEmpty) return;
    setState(() {
      _setId(value);
      _idError = null;
    });
  }

  Future<void> _delete() async {
    if (await confirmDialog(context,
        title: '删除设备',
        message: '移除「${device.displayName}」？该设备将从所有共享文件夹移除。',
        destructive: true)) {
      try {
        await ctrl.deleteDevice(device.deviceID);
        if (mounted) Navigator.of(context).pop();
      } catch (e) {
        if (mounted) showSnack(context, '删除失败: $e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? '添加设备' : '编辑设备'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _Section('设备'),
          if (isNew) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextFormField(
                controller: _idCtl,
                decoration: InputDecoration(
                  labelText: '设备 ID',
                  border: const OutlineInputBorder(),
                  errorText: _idError,
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.qr_code_scanner),
                        tooltip: '扫码添加',
                        onPressed: _scanId,
                      ),
                      IconButton(
                        icon: const Icon(Icons.content_paste),
                        tooltip: '粘贴',
                        onPressed: () async {
                          final data = await Clipboard.getData('text/plain');
                          if (data?.text != null) {
                            setState(() => _setId(data!.text!));
                          }
                        },
                      ),
                    ],
                  ),
                ),
                onChanged: (v) => device.raw['deviceID'] = v.trim(),
              ),
            ),
          ] else
            ListTile(
              leading: const Icon(Icons.qr_code_2),
              title: Text(device.displayName),
              subtitle: Text('${device.deviceID}', style: const TextStyle(fontSize: 11)),
              onTap: () => showDeviceIdDialog(context,
                  deviceId: device.deviceID, name: device.name),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextFormField(
              initialValue: device.name,
              decoration: const InputDecoration(
                  labelText: '名称（可选）', border: OutlineInputBorder()),
              onChanged: (v) => device.name = v,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextFormField(
              initialValue: device.addresses.join(', '),
              decoration: const InputDecoration(
                labelText: '地址（逗号分隔，dynamic = 动态发现）',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => device.addresses = v
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList(),
            ),
          ),
          ListTile(
            title: const Text('压缩'),
            subtitle: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'metadata', label: Text('元数据')),
                ButtonSegment(value: 'always', label: Text('全部')),
                ButtonSegment(value: 'never', label: Text('从不')),
              ],
              selected: {device.compression},
              onSelectionChanged: (s) =>
                  setState(() => device.compression = s.first),
            ),
          ),
          SwitchListTile(
            title: const Text('暂停此设备'),
            value: device.paused,
            onChanged: (v) => setState(() => device.paused = v),
          ),
          SwitchListTile(
            title: const Text('介绍人 (Introducer)'),
            subtitle: const Text('自动接受此设备介绍的设备与文件夹'),
            value: device.introducer,
            onChanged: (v) => setState(() => device.introducer = v),
          ),
          SwitchListTile(
            title: const Text('自动接受共享的文件夹'),
            value: device.autoAcceptFolders,
            onChanged: (v) => setState(() => device.autoAcceptFolders = v),
          ),
          _Section('速率限制（KiB/s，0 = 不限）'),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                child: TextFormField(
                  initialValue: device.maxSendKbps.toString(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: '上传', border: OutlineInputBorder()),
                  onChanged: (v) =>
                      device.maxSendKbps = int.tryParse(v) ?? 0,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: device.maxRecvKbps.toString(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: '下载', border: OutlineInputBorder()),
                  onChanged: (v) =>
                      device.maxRecvKbps = int.tryParse(v) ?? 0,
                ),
              ),
            ]),
          ),
          _Section('共享文件夹'),
          for (final f in ctrl.config?.folders ?? <FolderConfig>[])
            CheckboxListTile(
              value: f.deviceShared(device.deviceID.isEmpty ? '' : device.deviceID),
              title: Text(f.displayName),
              onChanged: (v) async {
                if (device.deviceID.isEmpty) return;
                final folder = ctrl.config?.folder(f.id);
                if (folder == null) return;
                final devices = folder.devices
                    .where((d) => d.deviceID != device.deviceID)
                    .toList();
                if (v == true) {
                  devices.add(FolderDeviceRef(deviceID: device.deviceID));
                }
                folder.devices = devices;
                await ctrl.saveFolder(folder);
                setState(() {});
              },
            ),
          if (!isNew)
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error),
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('删除设备'),
              ),
            ),
        ],
      ),
    );
  }
}

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
