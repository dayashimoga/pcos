import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/router/app_router.dart';
import '../repository/auth_repository.dart';

// ─── Events ─────────────────────────────────────────────
abstract class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object?> get props => [];
}

class AuthCheckRequested extends AuthEvent {
  const AuthCheckRequested();
}

class AuthLoginRequested extends AuthEvent {
  final String email;
  final String password;
  const AuthLoginRequested({required this.email, required this.password});
  @override
  List<Object?> get props => [email, password];
}

class AuthRegisterRequested extends AuthEvent {
  final String email;
  final String displayName;
  final String password;
  const AuthRegisterRequested({
    required this.email,
    required this.displayName,
    required this.password,
  });
  @override
  List<Object?> get props => [email, displayName, password];
}

class AuthLogoutRequested extends AuthEvent {
  const AuthLogoutRequested();
}

// ─── States ─────────────────────────────────────────────
abstract class AuthState extends Equatable {
  const AuthState();
  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthAuthenticated extends AuthState {
  final String userId;
  final String email;
  final String displayName;

  const AuthAuthenticated({
    required this.userId,
    required this.email,
    required this.displayName,
  });

  @override
  List<Object?> get props => [userId, email, displayName];
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthError extends AuthState {
  final String message;
  const AuthError(this.message);
  @override
  List<Object?> get props => [message];
}

// ─── BLoC ───────────────────────────────────────────────
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository authRepository;

  AuthBloc({required this.authRepository}) : super(const AuthInitial()) {
    on<AuthCheckRequested>(_onCheckRequested);
    on<AuthLoginRequested>(_onLoginRequested);
    on<AuthRegisterRequested>(_onRegisterRequested);
    on<AuthLogoutRequested>(_onLogoutRequested);
  }

  Future<void> _onCheckRequested(AuthCheckRequested event, Emitter<AuthState> emit) async {
    try {
      final user = await authRepository.getCurrentUser();
      if (user != null) {
        AppRouter.setAuthToken('valid');
        emit(AuthAuthenticated(
          userId: user['id'],
          email: user['email'],
          displayName: user['display_name'],
        ));
      } else {
        emit(const AuthUnauthenticated());
      }
    } catch (_) {
      emit(const AuthUnauthenticated());
    }
  }

  Future<void> _onLoginRequested(AuthLoginRequested event, Emitter<AuthState> emit) async {
    emit(const AuthLoading());
    try {
      final result = await authRepository.login(email: event.email, password: event.password);
      AppRouter.setAuthToken(result['tokens']['access_token']);
      emit(AuthAuthenticated(
        userId: result['user']['id'],
        email: result['user']['email'],
        displayName: result['user']['display_name'],
      ));
    } catch (e) {
      emit(AuthError(_extractErrorMessage(e)));
    }
  }

  Future<void> _onRegisterRequested(AuthRegisterRequested event, Emitter<AuthState> emit) async {
    emit(const AuthLoading());
    try {
      final result = await authRepository.register(
        email: event.email,
        displayName: event.displayName,
        password: event.password,
      );
      AppRouter.setAuthToken(result['tokens']['access_token']);
      emit(AuthAuthenticated(
        userId: result['user']['id'],
        email: result['user']['email'],
        displayName: result['user']['display_name'],
      ));
    } catch (e) {
      emit(AuthError(_extractErrorMessage(e)));
    }
  }

  Future<void> _onLogoutRequested(AuthLogoutRequested event, Emitter<AuthState> emit) async {
    await authRepository.logout();
    AppRouter.setAuthToken(null);
    emit(const AuthUnauthenticated());
  }

  String _extractErrorMessage(dynamic error) {
    if (error.toString().contains('Conflict')) {
      return 'This email is already registered';
    }
    if (error.toString().contains('Unauthorized')) {
      return 'Invalid email or password';
    }
    return 'An error occurred. Please try again.';
  }
}
