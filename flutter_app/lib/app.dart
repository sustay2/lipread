import 'package:flutter/material.dart';
import 'package:flutter_app/theme/light_theme.dart';
import 'package:flutter_app/services/router.dart';

class ELRLApp extends StatelessWidget {
  const ELRLApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lip Learning',
      debugShowCheckedModeBanner: false,
      theme: LightTheme.theme,
      themeMode: ThemeMode.light,
      onGenerateRoute: AppNavigator.onGenerateRoute,
      initialRoute: Routes.splash,
      navigatorObservers: [routeObserver],
    );
  }
}