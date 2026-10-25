import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/native_bridge.dart';

import '../../core/format.dart';
import '../../syncthing/controller.dart';
import '../../syncthing/models.dart';

/// 顶部服务状态卡片：运行状态、资源占用、启停。
class ServiceStatusCard extends StatelessWidget {
  const ServiceStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _StatusIcon(ctrl: context.watch<SyncthingController>()),
            const SizedBox(width: 12),
            Expanded(child: _StatusText(ctrl: context.watch<SyncthingController>())),
            _Trailing(ctrl: context.watch<SyncthingController>()),
          ],
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.ctrl});

  final SyncthingController ctrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return switch (ctrl.serviceState) {
      ServiceRunState.running => const Icon(Icons.check_circle, color: Colors.green),
      ServiceRunState.starting => const Icon(Icons.hourglass_top, color: Colors.orange),
      ServiceRunState.error => Icon(Icons.error, color: theme.colorScheme.error),
      ServiceRunState.stopped =>
        Icon(Icons.stop_circle, color: theme.colorScheme.outline),
    };
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText({required this.ctrl});

  final SyncthingController ctrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = ctrl.status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(switch (ctrl.serviceState) {
              ServiceRunState.running => 'Syncthing 运行中',
              ServiceRunState.starting => '正在启动…',
              ServiceRunState.error => '服务出错',
              ServiceRunState.stopped => '已停止',
            }, style: theme.textTheme.titleMedium),
        const SizedBox(height: 2),
        if (ctrl.serviceError != null)
          Text(
            ctrl.serviceError!,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          )
        else if (s != null && ctrl.apiReady)
          Text(
            '${ctrl.version?.version ?? ''} · CPU ${s.cpuPercent.toStringAsFixed(1)}% · '
            '内存 ${formatBytes(s.alloc)} · 已运行 ${formatDurationSec(s.uptime?.inSeconds ?? 0)}',
            style: theme.textTheme.bodySmall,
          )
        else
          Text('等待 API 就绪…', style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _Trailing extends StatelessWidget {
  const _Trailing({required this.ctrl});

  final SyncthingController ctrl;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (ctrl.isRunning && !ctrl.apiReady)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        IconButton.filledTonal(
          onPressed: ctrl.isRunning ? ctrl.stop : ctrl.start,
          icon: Icon(ctrl.isRunning ? Icons.stop : Icons.play_arrow),
          tooltip: ctrl.isRunning ? '停止服务' : '启动服务',
        ),
      ],
    );
  }
}

/// 设备 ID 二维码对话框（展示本机或对方 ID）。
Future<void> showDeviceIdDialog(BuildContext context,
    {required String deviceId, String? name}) {
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(name ?? '设备 ID'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: QrImageView(
              data: deviceId,
              size: 220,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          SelectableText(
            formatDeviceId(deviceId),
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Clipboard.setData(ClipboardData(text: deviceId)),
          child: const Text('复制'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

/// 通用确认对话框。
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = '确定',
  bool destructive = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error)
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return r ?? false;
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Theme.of(context).colorScheme.errorContainer : null,
      behavior: SnackBarBehavior.floating,
    ));
}

/// 文件夹状态的可读描述 + 颜色。
class FolderStateView {
  FolderStateView(this.text, this.color);

  final String text;
  final Color color;

  static FolderStateView of(BuildContext context, FolderConfig folder,
      FolderStatus? status, SyncthingController ctrl) {
    final theme = Theme.of(context);
    if (folder.paused) {
      return FolderStateView('已暂停', theme.colorScheme.outline);
    }
    if (status == null) {
      return FolderStateView('等待状态…', theme.colorScheme.outline);
    }
    switch (status.state) {
      case 'idle':
        if (status.error.isNotEmpty) {
          return FolderStateView('错误', theme.colorScheme.error);
        }
        if (status.needBytes > 0 || status.needTotalItems > 0) {
          return FolderStateView('等待同步', Colors.orange);
        }
        if (status.receiveOnlyTotalItems > 0) {
          return FolderStateView('有本地改动 (${status.receiveOnlyTotalItems})',
              Colors.orange);
        }
        return FolderStateView('已同步', Colors.green);
      case 'scanning':
        return FolderStateView(
          status.scanPercentage != null
              ? '正在扫描 ${status.scanPercentage!.toStringAsFixed(0)}%'
              : '正在扫描',
          Colors.blue,
        );
      case 'syncing':
        return FolderStateView(
          '正在同步 ${formatPercent(status.completion)}',
          Colors.blue,
        );
      case 'error':
        return FolderStateView('错误: ${status.error}', theme.colorScheme.error);
      case 'sync-preparing':
        return FolderStateView('准备同步', Colors.blue);
      case 'cleaning':
        return FolderStateView('正在清理版本', Colors.blue);
      case 'waiting':
        return FolderStateView('等待中', Colors.orange);
      case 'waiting-for-scan':
        return FolderStateView('等待扫描', Colors.orange);
      default:
        return FolderStateView(status.state, theme.colorScheme.outline);
    }
  }
}
