import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../syncthing/controller.dart';
import '../widgets/common.dart';

/// 日志页：MD3 风格日志卡片流 + 级别筛选。
///
/// 每行日志以独立的圆角卡片呈现：等级彩色图标 + 等宽正文 + 时间/包名脚注；
/// WARNING/ERROR 行用语义色容器高亮，便于快速扫视。
class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  String _filter = 'all'; // all | INF | WRN | ERR
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SyncthingController>();
    final lines = ctrl.processLog
        .where((l) => _filter == 'all' || l.level == _filter)
        .where((l) =>
            _query.isEmpty || l.text.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('日志'),
          bottom: const TabBar(tabs: [
            Tab(text: '运行日志'),
            Tab(text: '错误'),
          ]),
          actions: [
            IconButton(
              icon: const Icon(Icons.copy_all_outlined),
              tooltip: '复制全部',
              onPressed: () {
                final text = ctrl.processLog.map((l) => l.display).join('\n');
                Clipboard.setData(ClipboardData(text: text));
                showSnack(context, '已复制 ${ctrl.processLog.length} 行日志');
              },
            ),
          ],
        ),
        body: TabBarView(children: [
          Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '搜索日志…',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'all', label: Text('全部')),
                  ButtonSegment(value: 'INF', label: Text('信息')),
                  ButtonSegment(value: 'WRN', label: Text('警告')),
                  ButtonSegment(value: 'ERR', label: Text('错误')),
                ],
                selected: {_filter},
                onSelectionChanged: (s) => setState(() => _filter = s.first),
              ),
            ),
            Expanded(
              child: lines.isEmpty
                  ? Center(
                      child: Text(ctrl.isRunning ? '暂无匹配的日志' : '服务未运行，暂无日志'),
                    )
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                      itemCount: lines.length,
                      itemBuilder: (_, i) {
                        final line = lines[lines.length - 1 - i];
                        return _LogCard(line: line);
                      },
                    ),
            ),
          ]),
          _ErrorsTab(ctrl: ctrl),
        ]),
      ),
    );
  }
}

/// 单条日志的 MD3 卡片。
class _LogCard extends StatelessWidget {
  const _LogCard({required this.line});

  final ProcessLogLine line;

  static const _levelMeta = {
    'ERR': (Icons.error_outline, '错误'),
    'WRN': (Icons.warning_amber_rounded, '警告'),
    'INF': (Icons.info_outline, '信息'),
    'DBG': (Icons.bug_report_outlined, '调试'),
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, label) =
        _levelMeta[line.level] ?? (Icons.chevron_right, '');

    final Color fg;
    final Color? bg;
    switch (line.level) {
      case 'ERR':
        fg = scheme.onErrorContainer;
        bg = scheme.errorContainer;
      case 'WRN':
        fg = scheme.onSurface;
        bg = Colors.amber.withValues(alpha: 0.14);
      case 'DBG':
        fg = scheme.outline;
        bg = null;
      default:
        fg = scheme.onSurface;
        bg = scheme.surfaceContainerLow;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: bg == null ? Border.all(color: scheme.outlineVariant) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 18, color: fg),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    line.text,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      height: 1.35,
                      color: fg,
                    ),
                  ),
                  const SizedBox(height: 4),
                  DefaultTextStyle(
                    style: TextStyle(
                      fontSize: 10.5,
                      color: fg.withValues(alpha: 0.7),
                    ),
                    child: Row(children: [
                      Text(line.timeLabel),
                      if (label.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text('· $label'),
                      ],
                      if (line.pkg.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text('· ${line.pkg}'),
                      ],
                    ]),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 30,
              height: 30,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 14,
                icon: Icon(Icons.copy, color: fg.withValues(alpha: 0.6)),
                tooltip: '复制此行',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: line.display));
                  showSnack(context, '已复制');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorsTab extends StatelessWidget {
  const _ErrorsTab({required this.ctrl});

  final SyncthingController ctrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (ctrl.systemErrors.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_outlined, size: 48, color: scheme.outline),
            const SizedBox(height: 12),
            const Text('没有错误'),
          ],
        ),
      );
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: OutlinedButton.icon(
          onPressed: () => ctrl.clearErrors(),
          icon: const Icon(Icons.delete_outline),
          label: Text('清除全部 (${ctrl.systemErrors.length})'),
        ),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          itemCount: ctrl.systemErrors.length,
          itemBuilder: (_, i) {
            final e = ctrl.systemErrors[i];
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                leading: Icon(Icons.error_outline, color: scheme.onErrorContainer),
                title: SelectableText(
                  e.message,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onErrorContainer,
                  ),
                ),
                subtitle: Text(
                  _fmt(e.when),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: scheme.onErrorContainer.withValues(alpha: 0.7),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }

  String _fmt(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}
