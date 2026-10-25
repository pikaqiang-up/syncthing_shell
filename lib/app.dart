import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_prefs.dart';
import 'ui/shell.dart';

/// MD3 主题：动态取色（Android 12+ 壁纸色），失败时用品牌种子色；
/// 明暗模式默认跟随系统，可在设置中切换。
class SyncthingApp extends StatelessWidget {
  const SyncthingApp({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<AppPrefs>();
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        ColorScheme lightScheme;
        ColorScheme darkScheme;
        if (lightDynamic != null && darkDynamic != null) {
          lightScheme = lightDynamic.harmonized();
          darkScheme = darkDynamic.harmonized();
        } else {
          lightScheme = ColorScheme.fromSeed(seedColor: const Color(0xFF0891B1));
          darkScheme = ColorScheme.fromSeed(
            seedColor: const Color(0xFF0891B1),
            brightness: Brightness.dark,
          );
        }
        return MaterialApp(
          title: 'Syncthing',
          debugShowCheckedModeBanner: false,
          themeMode: switch (prefs.themeMode) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          },
          theme: _theme(lightScheme),
          darkTheme: _theme(darkScheme),
          home: const HomeShell(),
        );
      },
    );
  }

  ThemeData _theme(ColorScheme scheme) {
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    return base.copyWith(
      appBarTheme: const AppBarTheme(centerTitle: false),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
    );
  }
}
