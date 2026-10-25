import 'package:flutter/material.dart';

import 'devices/devices_page.dart';
import 'folders/folders_page.dart';
import 'logs/logs_page.dart';
import 'overview/overview_page.dart';
import 'settings/settings_page.dart';

/// 底部导航壳：状态总览 / 文件夹 / 设备 / 日志 / 设置。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _pages = [
    OverviewPage(),
    FoldersPage(),
    DevicesPage(),
    LogsPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 点击空白处收起键盘，避免遮挡底部导航
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: IndexedStack(index: _index, children: _pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: '状态总览',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: '文件夹',
          ),
          NavigationDestination(
            icon: Icon(Icons.devices_outlined),
            selectedIcon: Icon(Icons.devices),
            label: '设备',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: '日志',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
