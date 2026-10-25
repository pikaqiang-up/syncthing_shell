import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/app_prefs.dart';
import 'syncthing/controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await AppPrefs.load();
  final controller = SyncthingController(prefs: prefs);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: prefs),
        ChangeNotifierProvider.value(value: controller),
      ],
      child: const SyncthingApp(),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    controller.bootstrap();
  });
}
