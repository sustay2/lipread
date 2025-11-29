import 'package:flutter/material.dart';
import 'package:flutter_app/common/theme/app_theme.dart';
import 'package:flutter_app/services/router.dart';
import 'package:flutter_app/services/theme_controller.dart';
import 'package:provider/provider.dart';

class ELRLApp extends StatelessWidget {
  const ELRLApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ThemeController(),
      child: Consumer<ThemeController>(
        builder: (context, theme, _) {
          return MaterialApp(
            title: 'Lip Learning',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: theme.mode,
            onGenerateRoute: AppNavigator.onGenerateRoute,
            initialRoute: Routes.splash,
            navigatorObservers: [routeObserver],
          );
        },
      ),
    );
  }
}