import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/di/service_locator.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/bloc/auth_bloc.dart';

/// Global theme mode notifier — accessible from Settings to toggle light/dark.
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  try {
    await setupServiceLocator();
  } catch (e, stack) {
    debugPrint('Service locator error during startup: $e\n$stack');
  }
  runApp(const PCOSApp());
}

class PCOSApp extends StatelessWidget {
  const PCOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AuthBloc>(
      create: (_) => getIt<AuthBloc>(),
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: themeNotifier,
        builder: (_, mode, __) => MaterialApp.router(
          title: 'PCOS - Personal Cloud OS',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode,
          routerConfig: AppRouter.router,
        ),
      ),
    );
  }
}
