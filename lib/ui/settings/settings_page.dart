import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_prefs.dart';
import '../../core/native_bridge.dart';
import '../../syncthing/controller.dart';
import '../../syncthing/models.dart';
import '../widgets/common.dart';

/// 设置页：壳设置 + Syncthing 全部设置（对齐 web 前端设置弹窗）。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SyncthingController>();
    final prefs = context.watch<AppPrefs>();
    final options = ctrl.config?.options;
    final gui = ctrl.config?.gui;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _Section('外观'),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('主题模式'),
            subtitle: Text(switch (prefs.themeMode) {
              'light' => '浅色',
              'dark' => '深色',
              _ => '跟随系统',
            }),
            onTap: () => _pickTheme(context, prefs),
          ),
          _Section('服务'),
          SwitchListTile(
            secondary: const Icon(Icons.rocket_launch_outlined),
            title: const Text('打开 App 时自动启动'),
            subtitle: const Text('关闭后需在「状态总览」手动启动服务'),
            value: prefs.autoStartOnOpen,
            onChanged: (v) => prefs.autoStartOnOpen = v,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.power_settings_new),
            title: const Text('开机自动启动'),
            value: prefs.startOnBoot,
            onChanged: (v) => prefs.startOnBoot = v,
          ),
          FutureBuilder<bool>(
            future: NativeBridge.instance.isAllFilesAccessGranted(),
            builder: (context, snap) => ListTile(
              leading: const Icon(Icons.folder_shared_outlined),
              title: const Text('所有文件访问权限'),
              subtitle: Text(snap.data == true ? '已授予' : '未授予（同步共享存储需要）'),
              trailing: snap.data == true
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : const Icon(Icons.warning, color: Colors.orange),
              onTap: () => NativeBridge.instance.requestAllFilesAccess(),
            ),
          ),
          FutureBuilder<bool>(
            future: NativeBridge.instance.isIgnoringBatteryOptimizations(),
            builder: (context, snap) => ListTile(
              leading: const Icon(Icons.battery_saver),
              title: const Text('忽略电池优化'),
              subtitle: Text(snap.data == true ? '已忽略' : '建议忽略以避免被杀'),
              trailing: snap.data == true
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : const Icon(Icons.warning, color: Colors.orange),
              onTap: () =>
                  NativeBridge.instance.requestIgnoreBatteryOptimizations(),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('在浏览器中打开 Web 界面'),
            subtitle: Text(ctrl.info?.webUiUrl ?? '服务未启动'),
            enabled: ctrl.apiReady,
            onTap: () => NativeBridge.instance.openWebUi(ctrl.info!.webUiUrl),
          ),
          _GatedOnService(
            enabled: ctrl.apiReady,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            _Section('常规（Syncthing）'),
            if (ctrl.ownDevice != null)
              _EditTextTile(
                icon: Icons.badge_outlined,
                label: '本机设备名称',
                initial: ctrl.ownDevice!.name,
                onSaved: (v) async {
                  final d = ctrl.ownDevice!;
                  d.name = v;
                  await ctrl.saveDevice(d);
                },
              ),
            if (options != null) ...[
              SwitchListTile(
                secondary: const Icon(Icons.public),
                title: const Text('全局发现（Global Discovery）'),
                value: options.globalAnnounceEnabled,
                onChanged: (v) => ctrl.patchOptions({'globalAnnounceEnabled': v}),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.lan_outlined),
                title: const Text('本地发现（Local Discovery）'),
                value: options.localAnnounceEnabled,
                onChanged: (v) => ctrl.patchOptions({'localAnnounceEnabled': v}),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.compare_arrows),
                title: const Text('中继（Relays）'),
                subtitle: const Text('无法直连时通过中继服务器中转'),
                value: options.relaysEnabled,
                onChanged: (v) => ctrl.patchOptions({'relaysEnabled': v}),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.router_outlined),
                title: const Text('NAT 穿透（UPnP）'),
                value: options.natEnabled,
                onChanged: (v) => ctrl.patchOptions({'natEnabled': v}),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.insights_outlined),
                title: const Text('匿名使用报告'),
                subtitle: Text(_urLabel(options.urAccepted)),
                value: options.urAccepted == 1,
                onChanged: (v) => ctrl.setUsageReport(v),
              ),
            ],
            _Section('连接（Syncthing）'),
            if (options != null) ...[
              _EditTextTile(
                icon: Icons.settings_ethernet,
                label: '监听地址（逗号分隔）',
                initial: options.listenAddresses.join(', '),
                onSaved: (v) => ctrl.patchOptions({
                  'listenAddresses': v
                      .split(',')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty)
                      .toList()
                }),
              ),
              _RateTile(ctrl: ctrl, options: options),
              SwitchListTile(
                secondary: const Icon(Icons.speed),
                title: const Text('局域网也限速'),
                value: options.limitBandwidthInLan,
                onChanged: (v) => ctrl.patchOptions({'limitBandwidthInLan': v}),
              ),
            ],
            _Section('Web 界面（浏览器访问）'),
            if (gui != null) ...[
              _EditTextTile(
                icon: Icons.language,
                label: 'GUI 监听地址',
                initial: gui.address,
                onSaved: (v) async {
                  await ctrl.putGui({...gui.toJson(), 'address': v});
                },
                hint: '修改后需重启 Syncthing 生效',
              ),
              _EditTextTile(
                icon: Icons.person_outline,
                label: 'GUI 用户名（可空）',
                initial: gui.user,
                onSaved: (v) async {
                  await ctrl.putGui({...gui.toJson(), 'user': v});
                },
              ),
              _EditTextTile(
                icon: Icons.password,
                label: 'GUI 密码（可空）',
                initial: '',
                obscure: true,
                onSaved: (v) async {
                  if (v.isEmpty) return;
                  await ctrl.putGui({...gui.toJson(), 'password': v});
                },
                hint: '留空不修改；浏览器访问时需输入',
              ),
              ListTile(
                leading: const Icon(Icons.key),
                title: const Text('API Key'),
                subtitle: Text(gui.apiKey,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                onTap: () => _copy(context, gui.apiKey, 'API Key'),
              ),
            ],
            _Section('动作'),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('全部重新扫描'),
              onTap: () async {
                await ctrl.rescanAll();
                if (context.mounted) showSnack(context, '已触发全部扫描');
              },
            ),
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('重启 Syncthing'),
              onTap: () => ctrl.restart(),
            ),
            _Section('高级'),
            ListTile(
              leading: const Icon(Icons.data_object),
              title: const Text('编辑原始配置（JSON）'),
              subtitle: const Text('直接读写完整配置，危险操作'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const RawConfigPage())),
            ),
              ],
            ),
          ),
          _Section('关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('版本'),
            subtitle: Text(
              '内嵌 Syncthing: ${ctrl.version?.longVersion ?? '—'}\n'
              '协议版本: ${ctrl.version?.version ?? ''}\n'
              '壳: syncthing_flutter 1.0.0',
            ),
          ),
          if (ctrl.configNeedsRestart)
            Card(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              margin: const EdgeInsets.all(16),
              child: ListTile(
                leading: const Icon(Icons.restart_alt),
                title: const Text('有配置等待重启生效'),
                trailing: TextButton(
                  onPressed: () => ctrl.restart(),
                  child: const Text('立即重启'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _pickTheme(BuildContext context, AppPrefs prefs) {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('主题模式'),
        children: [
          for (final (v, label) in const [
            ('system', '跟随系统'),
            ('light', '浅色'),
            ('dark', '深色'),
          ])
            RadioListTile<String>(
              value: v,
              groupValue: prefs.themeMode,
              title: Text(label),
              onChanged: (sel) {
                prefs.themeMode = sel!;
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
    );
  }

  void _copy(BuildContext context, String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    showSnack(context, '$what 已复制');
  }
}

String _urLabel(int v) => switch (v) {
  1 => '已同意',
  0 => '已拒绝',
  _ => '未决定',
};

class _RateTile extends StatelessWidget {
  const _RateTile({required this.ctrl, required this.options});

  final SyncthingController ctrl;
  final OptionsConfig options;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.speed_outlined),
      title: const Text('速率限制（KiB/s，0 = 不限）'),
      subtitle: Text('上传 ${options.maxSendKbps} · 下载 ${options.maxRecvKbps}'),
      onTap: () => _editRates(context),
    );
  }

  Future<void> _editRates(BuildContext context) async {
    final send = TextEditingController(text: options.maxSendKbps.toString());
    final recv = TextEditingController(text: options.maxRecvKbps.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('速率限制'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: send,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '上传 KiB/s'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: recv,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '下载 KiB/s'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('保存')),
        ],
      ),
    );
    if (ok == true) {
      await ctrl.patchOptions({
        'maxSendKbps': int.tryParse(send.text) ?? 0,
        'maxRecvKbps': int.tryParse(recv.text) ?? 0,
      });
    }
  }
}

class _EditTextTile extends StatelessWidget {
  const _EditTextTile({
    required this.icon,
    required this.label,
    required this.initial,
    required this.onSaved,
    this.hint,
    this.obscure = false,
  });

  final IconData icon;
  final String label;
  final String initial;
  final Future<void> Function(String) onSaved;
  final String? hint;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(initial.isEmpty ? (hint ?? '（空）') : initial,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () async {
        final ctl = TextEditingController(text: initial);
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(label),
            content: TextField(
              controller: ctl,
              obscureText: obscure,
              decoration: InputDecoration(hintText: hint),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
              FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('保存')),
            ],
          ),
        );
        if (ok == true) {
          try {
            await onSaved(ctl.text.trim());
            if (context.mounted) showSnack(context, '已保存');
          } catch (e) {
            if (context.mounted) showSnack(context, '保存失败: $e', error: true);
          }
        }
      },
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

/// 高级：完整配置 JSON 编辑器。
class RawConfigPage extends StatefulWidget {
  const RawConfigPage({super.key});

  @override
  State<RawConfigPage> createState() => _RawConfigPageState();
}

class _RawConfigPageState extends State<RawConfigPage> {
  final _ctl = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final ctrl = context.read<SyncthingController>();
    final cfg = ctrl.config ?? Config.empty();
    _ctl.text = const JsonEncoder.withIndent('  ').convert(cfg.toJson());
    setState(() => _loaded = true);
  }

  Future<void> _save() async {
    final ctrl = context.read<SyncthingController>();
    try {
      final map = jsonDecode(_ctl.text) as Map<String, dynamic>;
      await ctrl.putRawConfig(map);
      if (mounted) showSnack(context, '配置已写入');
      _reload();
    } catch (e) {
      if (mounted) showSnack(context, '保存失败: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('原始配置'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新加载',
            onPressed: _reload,
          ),
          TextButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: _loaded
          ? Padding(
              padding: const EdgeInsets.all(8),
              child: TextField(
                controller: _ctl,
                maxLines: null,
                expands: true,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'config JSON',
                ),
                onChanged: (_) {},
              ),
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}

/// 服务未运行（API 未就绪）时：显示提示横幅并禁用其下的 Syncthing 设置项。
class _GatedOnService extends StatelessWidget {
  const _GatedOnService({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (enabled) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          color: scheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: scheme.onSecondaryContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Syncthing 服务未运行，以下设置暂不可用。请先到「状态总览」启动服务。',
                    style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
        Opacity(
          opacity: 0.45,
          child: IgnorePointer(
            ignoring: true,
            child: child,
          ),
        ),
      ],
    );
  }
}
