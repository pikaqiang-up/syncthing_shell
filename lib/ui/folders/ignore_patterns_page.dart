import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../syncthing/controller.dart';
import '../widgets/common.dart';

/// 忽略模式编辑器（等价 web 前端 Ignore Patterns 弹窗，含规则测试）。
class IgnorePatternsPage extends StatefulWidget {
  const IgnorePatternsPage({super.key, required this.folderId});

  final String folderId;

  @override
  State<IgnorePatternsPage> createState() => _IgnorePatternsPageState();
}

class _IgnorePatternsPageState extends State<IgnorePatternsPage> {
  final _ctl = TextEditingController();
  final _testCtl = TextEditingController();
  bool _loaded = false;
  bool _saving = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final lines = await context.read<SyncthingController>().getIgnores(widget.folderId);
      _ctl.text = lines.join('\n');
    } catch (_) {}
    setState(() => _loaded = true);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final lines = _ctl.text.split('\n');
      await context.read<SyncthingController>().setIgnores(widget.folderId, lines);
      if (mounted) {
        showSnack(context, '已保存，稍后生效');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) showSnack(context, '保存失败: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    if (_testCtl.text.isEmpty) return;
    try {
      final r = await context
          .read<SyncthingController>()
          .matchIgnores(widget.folderId, _testCtl.text);
      setState(() {
        _testResult = r.ignored
            ? '会被忽略（匹配: ${r.matched.join(', ')}）'
            : '不会被忽略';
      });
    } catch (e) {
      setState(() => _testResult = '测试失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('忽略模式'),
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
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _ctl,
                  maxLines: 14,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '忽略模式（每行一条）',
                    alignLabelWithHint: true,
                    helperText: '例: *.tmp  /photos/private  !important.tmp  (?i)*.iso',
                  ),
                ),
                const SizedBox(height: 16),
                const Text('测试规则'),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _testCtl,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: '文件名',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(onPressed: _test, child: const Text('测试')),
                ]),
                if (_testResult != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_testResult!),
                  ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}
