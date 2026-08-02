import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../network/api_client.dart';
import '../router/app_router.dart';
import '../../features/auth/bloc/auth_bloc.dart';
import '../../features/auth/repository/auth_repository.dart';
import '../../features/devices/bloc/device_bloc.dart';
import '../../features/devices/repository/device_repository.dart';
import '../../features/files/bloc/file_bloc.dart';
import '../../features/files/repository/file_repository.dart';

final getIt = GetIt.instance;

/// Initialize all dependencies. Must be called before runApp.
Future<void> setupServiceLocator() async {
  // ─── Async singletons ─────────────────────────────────
  final prefs = await SharedPreferences.getInstance();
  getIt.registerSingleton<SharedPreferences>(prefs);

  // ─── Core ─────────────────────────────────────────────
  getIt.registerLazySingleton<ApiClient>(
    () => ApiClient(prefs: getIt<SharedPreferences>()),
  );

  // ─── Repositories ─────────────────────────────────────
  getIt.registerLazySingleton<AuthRepository>(
    () => AuthRepository(
      apiClient: getIt<ApiClient>(),
      prefs: getIt<SharedPreferences>(),
    ),
  );
  getIt.registerLazySingleton<DeviceRepository>(
    () => DeviceRepository(apiClient: getIt<ApiClient>()),
  );
  getIt.registerLazySingleton<FileRepository>(
    () => FileRepository(apiClient: getIt<ApiClient>()),
  );

  // ─── BLoCs ────────────────────────────────────────────
  getIt.registerFactory<AuthBloc>(
    () => AuthBloc(authRepository: getIt<AuthRepository>()),
  );
  getIt.registerFactory<DeviceBloc>(
    () => DeviceBloc(deviceRepository: getIt<DeviceRepository>()),
  );
  getIt.registerFactory<FileBloc>(
    () => FileBloc(fileRepository: getIt<FileRepository>()),
  );

  // ─── Initialize auth state ────────────────────────────
  // Set initial auth token for router guard
  final token = prefs.getString('pcos_access_token');
  AppRouter.setAuthToken(token);
}
