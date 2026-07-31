import 'package:flutter/material.dart';

import 'state/app_controller.dart';
import 'ui/app_shell.dart';

class V2BoxKitApp extends StatefulWidget {
  const V2BoxKitApp({super.key});

  @override
  State<V2BoxKitApp> createState() => _V2BoxKitAppState();
}

class _V2BoxKitAppState extends State<V2BoxKitApp> {
  late final AppController controller;
  late final Future<void> loading;

  @override
  void initState() {
    super.initState();
    controller = AppController();
    loading = controller.load();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff2f6fed),
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: 'V2BoxKit',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xfff5f7fb),
        cardTheme: const CardThemeData(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(18)),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
        ),
      ),
      home: FutureBuilder<void>(
        future: loading,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return AppShell(controller: controller);
        },
      ),
    );
  }
}
