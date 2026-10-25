import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../syncthing/controller.dart';
import '../../syncthing/models.dart';
import '../folders/folder_edit_page.dart' show formatDeviceIdShort;
import '../widgets/common.dart';
import 'device_edit_page.dart';

/// 设备列表：本机 + 远程 + 待定。
class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SyncthingController>();
    final devices = ctrl.config?.devices ?? <DeviceConfig>[];
    return Scaffold(
      appBar: AppBar(title: const Text('设备')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const DeviceEditPage(deviceID: null),
        )),
        icon: const Icon(Icons.add),
        label: const Text('添加设备'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          if (ctrl.myID.isNotEmpty)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListTile(
                leading: const Icon(Icons.smartphone),
                title: Text(ctrl.ownDevice?.name ?? '本机'),
                subtitle: const Text('本设备', style: TextStyle(fontSize: 12)),
                trailing: IconButton(
                  icon: const Icon(Icons.qr_code_2),
                  onPressed: () => showDeviceIdDialog(context,
                      deviceId: ctrl.myID, name: ctrl.ownDevice?.name),
                ),
                onTap: () => showDeviceIdDialog(context,
                    deviceId: ctrl.myID, name: ctrl.ownDevice?.name),
              ),
            ),
          for (final d in devices)
            if (d.deviceID != ctrl.myID) _DeviceTile(device: d),
          if (ctrl.pendingDevices.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text('待添加设备',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: Theme.of(context).colorScheme.primary)),
            ),
            for (final p in ctrl.pendingDevices)
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.add_link),
                  title: Text(p.name.isEmpty ? formatDeviceId(p.deviceID) : p.name),
                  subtitle: Text('${p.address}',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                          onPressed: () => ctrl.acceptPendingDevice(p.deviceID),
                          child: const Text('添加')),
                      TextButton(
                          onPressed: () => ctrl.dismissPendingDevice(p.deviceID),
                          child: const Text('忽略')),
                    ],
                  ),
                ),
              ),
          ],
          if (devices.where((d) => d.deviceID != ctrl.myID).isEmpty &&
              ctrl.pendingDevices.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('还没有远程设备，点击右下角添加')),
            ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device});

  final DeviceConfig device;

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SyncthingController>();
    final conn = ctrl.connections?.connections[device.deviceID];
    final theme = Theme.of(context);
    final (stateText, color) = switch ((
      device.paused,
      conn?.connected == true
    )) {
      (true, _) => ('已暂停', theme.colorScheme.outline),
      (false, true) => ('已连接 ${conn?.address ?? ''}', Colors.green),
      (_, _) => (
          '未连接${conn == null ? '' : ' · 最后 ${ctrl.deviceStats[device.deviceID]?.lastSeen != null ? formatTime(ctrl.deviceStats[device.deviceID]!.lastSeen) : ''}'}',
          theme.colorScheme.outline
        ),
    };
    final foldersShared = ctrl.config?.folders
            .where((f) => f.deviceShared(device.deviceID))
            .length ??
        0;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Badge(
          isLabelVisible: conn?.connected == true,
          smallSize: 10,
          child: const Icon(Icons.devices_other),
        ),
        title: Text(device.displayName),
        subtitle: Text(
          '$stateText\n共享 $foldersShared 个文件夹 · ${formatDeviceIdShort(device.deviceID)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color, fontSize: 12),
        ),
        isThreeLine: true,
        trailing: device.paused
            ? const Icon(Icons.pause_circle_outline)
            : const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => DeviceEditPage(deviceID: device.deviceID),
        )),
      ),
    );
  }
}
