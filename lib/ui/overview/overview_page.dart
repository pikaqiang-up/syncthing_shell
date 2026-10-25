import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../syncthing/controller.dart';
import '../../syncthing/models.dart';
import '../devices/device_edit_page.dart';
import '../folders/folder_detail_page.dart';
import '../widgets/common.dart';

/// 状态总览：本机状态、文件夹概要、设备概要、最近更改。
class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SyncthingController>();
    return Scaffold(
      appBar: AppBar(title: const Text('状态总览')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const ServiceStatusCard(),
          if (ctrl.apiReady) ...[
            _SyncBanner(ctrl: ctrl),
            _ThisDeviceCard(ctrl: ctrl),
            if (ctrl.pendingDevices.isNotEmpty) _PendingDevicesCard(ctrl: ctrl),
            if (ctrl.pendingFolders.isNotEmpty) _PendingFoldersCard(ctrl: ctrl),
            const _SectionHeader('文件夹'),
            ...ctrl.config?.folders.map((f) => _FolderTile(ctrl: ctrl, folder: f)) ?? [],
            const _SectionHeader('设备'),
            ..._deviceTiles(context, ctrl),
            const _SectionHeader('最近更改'),
            _RecentChangesCard(ctrl: ctrl),
            const _SectionHeader('统计'),
            _StatsCard(ctrl: ctrl),
          ] else if (!ctrl.isRunning)
            const _StartHint(),
        ],
      ),
    );
  }

  List<Widget> _deviceTiles(BuildContext context, SyncthingController ctrl) {
    final tiles = <Widget>[];
    for (final d in ctrl.config?.devices ?? <DeviceConfig>[]) {
      if (d.deviceID == ctrl.myID) continue;
      tiles.add(_DeviceTile(ctrl: ctrl, device: d));
    }
    if (tiles.isEmpty) {
      tiles.add(const Padding(
        padding: EdgeInsets.all(16),
        child: Text('还没有其他设备，去「设备」页添加。'),
      ));
    }
    return tiles;
  }
}

/// 同步进行中的聚合横幅：正在同步/扫描的文件夹进度 + 全局速率。
class _SyncBanner extends StatelessWidget {
  const _SyncBanner({required this.ctrl});

  final SyncthingController ctrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = <({String label, String text, double progress})>[];
    for (final f in ctrl.config?.folders ?? <FolderConfig>[]) {
      if (f.paused) continue;
      final st = ctrl.folderStatuses[f.id];
      if (st == null) continue;
      if (st.state == 'syncing') {
        active.add((
          label: f.displayName,
          text: '同步中 ${formatPercent(st.completion)} · 差 ${formatBytes(st.needBytes)}',
          progress: st.completion / 100,
        ));
      } else if (st.state == 'scanning') {
        active.add((
          label: f.displayName,
          text: '扫描中${st.scanPercentage != null ? ' ${st.scanPercentage!.toStringAsFixed(0)}%' : ''}',
          progress: st.scanPercentage != null ? st.scanPercentage! / 100 : -1,
        ));
      }
    }
    if (active.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(width: 10),
              Text('正在同步',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: scheme.onPrimaryContainer)),
              const Spacer(),
              Text(
                '↑ ${formatRate(ctrl.connections?.totalOutRate)}   '
                '↓ ${formatRate(ctrl.connections?.totalInRate)}',
                style: TextStyle(
                    fontSize: 12, color: scheme.onPrimaryContainer),
              ),
            ]),
            for (final a in active.take(3)) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: Text(a.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onPrimaryContainer))),
                Text(a.text,
                    style: TextStyle(
                        fontSize: 12, color: scheme.onPrimaryContainer)),
              ]),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: a.progress < 0 ? null : a.progress,
                minHeight: 5,
              ),
            ],
            if (active.length > 3)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('…以及另外 ${active.length - 3} 个文件夹',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onPrimaryContainer)),
              ),
          ],
        ),
      ),
    );
  }
}

class _StartHint extends StatelessWidget {
  const _StartHint();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            const SizedBox(height: 48),
            Icon(Icons.power_settings_new,
                size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            const Text('服务未运行，点击上方按钮启动'),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

class _ThisDeviceCard extends StatelessWidget {
  const _ThisDeviceCard({required this.ctrl});

  final SyncthingController ctrl;

  @override
  Widget build(BuildContext context) {
    final own = ctrl.ownDevice;
    final status = ctrl.status;
    final addresses = status?.connectionServiceStatus.keys
            .where((k) => (status.connectionServiceStatus[k] as Map?)?['error'] == null)
            .join('  ') ??
        '';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.smartphone),
        title: Text(own?.name ?? '本机'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('↓ ${formatRate(ctrl.connections?.totalInRate)}   '
                '↑ ${formatRate(ctrl.connections?.totalOutRate)}'),
            if (addresses.isNotEmpty)
              Text(addresses,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.qr_code_2),
          tooltip: '设备 ID 二维码',
          onPressed: () => showDeviceIdDialog(context,
              deviceId: ctrl.myID, name: own?.name),
        ),
        onTap: () => showDeviceIdDialog(context,
            deviceId: ctrl.myID, name: own?.name),
      ),
    );
  }
}

class _PendingDevicesCard extends StatelessWidget {
  const _PendingDevicesCard({required this.ctrl});

  final SyncthingController ctrl;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (final p in ctrl.pendingDevices)
            ListTile(
              leading: const Icon(Icons.add_link),
              title: Text(p.name.isEmpty ? '新设备' : p.name),
              subtitle: Text(formatDeviceId(p.deviceID),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () async {
                      await ctrl.acceptPendingDevice(p.deviceID);
                      if (context.mounted) showSnack(context, '已添加设备');
                    },
                    child: const Text('添加'),
                  ),
                  TextButton(
                    onPressed: () => ctrl.dismissPendingDevice(p.deviceID),
                    child: const Text('忽略'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PendingFoldersCard extends StatelessWidget {
  const _PendingFoldersCard({required this.ctrl});

  final SyncthingController ctrl;

  @override
  Widget build(BuildContext context) {
    final entries = <({String device, PendingFolder folder})>[];
    ctrl.pendingFolders.forEach((device, folders) {
      for (final f in folders) {
        entries.add((device: device, folder: f));
      }
    });
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (final e in entries)
            ListTile(
              leading: Icon(Icons.create_new_folder_outlined),
              title: Text(e.folder.label.isEmpty ? e.folder.id : e.folder.label),
              subtitle: Text(
                  '来自 ${ctrl.config?.device(e.device)?.displayName ?? formatDeviceId(e.device)}'),
              trailing: TextButton(
                onPressed: () => _acceptFolder(context, ctrl, e),
                child: const Text('添加'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _acceptFolder(BuildContext context, SyncthingController ctrl,
      ({String device, PendingFolder folder}) e) async {
    final pathCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('添加文件夹 ${e.folder.label.isEmpty ? e.folder.id : e.folder.label}'),
        content: TextField(
          controller: pathCtl,
          decoration: const InputDecoration(
            labelText: '存储路径',
            hintText: '/storage/emulated/0/...',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('添加')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      try {
        await ctrl.acceptPendingFolder(e.folder.id, e.device,
            label: e.folder.label, path: pathCtl.text.trim());
        if (context.mounted) showSnack(context, '已添加文件夹');
      } catch (err) {
        if (context.mounted) showSnack(context, '添加失败: $err', error: true);
      }
    }
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({required this.ctrl, required this.folder});

  final SyncthingController ctrl;
  final FolderConfig folder;

  @override
  Widget build(BuildContext context) {
    final status = ctrl.folderStatuses[folder.id];
    final view = FolderStateView.of(context, folder, status, ctrl);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        title: Text(folder.displayName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(view.text,
                style: TextStyle(color: view.color, fontSize: 13)),
            if (status != null)
              Text(
                '${formatBytes(status.globalBytes)} · '
                '${status.globalFiles + status.globalDirectories} 项',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        trailing: folder.paused
            ? const Icon(Icons.pause_circle_outline)
            : status != null && status.state == 'syncing'
                ? SizedBox(
                    width: 40,
                    child: LinearProgressIndicator(
                        value: status.completion / 100),
                  )
                : const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => FolderDetailPage(folderId: folder.id),
        )),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.ctrl, required this.device});

  final SyncthingController ctrl;
  final DeviceConfig device;

  @override
  Widget build(BuildContext context) {
    final conn = ctrl.connections?.connections[device.deviceID];
    final theme = Theme.of(context);
    String stateText;
    Color color;
    if (device.paused) {
      stateText = '已暂停';
      color = theme.colorScheme.outline;
    } else if (conn?.connected == true) {
      stateText = '已连接 · ${conn?.address ?? ''}';
      color = Colors.green;
    } else {
      final last = ctrl.deviceStats[device.deviceID]?.lastSeen;
      stateText = last == null ? '未连接' : '最后可见 ${formatTime(last)}';
      color = theme.colorScheme.outline;
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Icon(
          conn?.connected == true ? Icons.laptop_windows : Icons.laptop_windows,
          color: conn?.connected == true ? Colors.green : null,
        ),
        title: Text(device.displayName),
        subtitle: Text(stateText, style: TextStyle(color: color, fontSize: 13)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => DeviceEditPage(deviceID: device.deviceID),
        )),
      ),
    );
  }
}

class _RecentChangesCard extends StatelessWidget {
  const _RecentChangesCard({required this.ctrl});

  final SyncthingController ctrl;

  @override
  Widget build(BuildContext context) {
    if (ctrl.recentChanges.isEmpty) {
      return const Card(
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('暂无更改记录（同步发生后显示）'),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (final c in ctrl.recentChanges.take(15))
            ListTile(
              dense: true,
              leading: Icon(
                switch (c.action) {
                  'added' => Icons.add_circle_outline,
                  'deleted' => Icons.remove_circle_outline,
                  _ => Icons.edit_outlined,
                },
                size: 20,
              ),
              title: Text(
                c.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                '${c.folderLabel.isEmpty ? c.folderId : c.folderLabel} · '
                '${c.local ? '本机' : '远程'}${c.byDevice.isEmpty ? '' : ' · ${c.byDevice}'} · ${formatTime(c.time)}',
                style: const TextStyle(fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.ctrl});

  final SyncthingController ctrl;

  @override
  Widget build(BuildContext context) {
    // 全局 + 本地统计（对齐 web 前端的右抽屉统计）
    int gFiles = 0, gDirs = 0, gBytes = 0, gDeleted = 0;
    int lFiles = 0, lDirs = 0, lBytes = 0, lDeleted = 0;
    for (final s in ctrl.folderStatuses.values) {
      gFiles += s.globalFiles;
      gDirs += s.globalDirectories;
      gBytes += s.globalBytes;
      gDeleted += s.globalDeleted;
      lFiles += s.localFiles;
      lDirs += s.localDirectories;
      lBytes += s.localBytes;
      lDeleted += s.localDeleted;
    }
    Widget row(String label, String global, String local) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Expanded(child: Text(label)),
              SizedBox(
                  width: 110,
                  child: Text(global,
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontSize: 13))),
              SizedBox(
                  width: 110,
                  child: Text(local,
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontSize: 13))),
            ],
          ),
        );
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                const Expanded(child: Text('')),
                SizedBox(
                    width: 110,
                    child: Text('全局',
                        textAlign: TextAlign.end,
                        style: Theme.of(context).textTheme.labelSmall)),
                SizedBox(
                    width: 110,
                    child: Text('本机',
                        textAlign: TextAlign.end,
                        style: Theme.of(context).textTheme.labelSmall)),
              ]),
            ),
            row('文件', '$gFiles', '$lFiles'),
            row('目录', '$gDirs', '$lDirs'),
            row('已删除', '$gDeleted', '$lDeleted'),
            row('数据', formatBytes(gBytes), formatBytes(lBytes)),
          ],
        ),
      ),
    );
  }
}
