import 'package:flutter/material.dart';
import 'package:flutter_app/common/services/theme_controller.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/services/router.dart';
import 'package:provider/provider.dart';

class ELRLApp extends StatelessWidget {
  const ELRLApp({
    super.key,
    required this.themeController,
  });

  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ThemeController>.value(
      value: themeController,
      child: Consumer<ThemeController>(
        builder: (context, theme, _) {
          return MaterialApp(
            title: 'Lip Learning',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: theme.themeMode,
            onGenerateRoute: AppNavigator.onGenerateRoute,
            initialRoute: Routes.splash,
            navigatorObservers: [routeObserver],
          );
        },
      ),
    );
  }
}