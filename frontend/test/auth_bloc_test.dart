import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pcos_frontend/features/auth/bloc/auth_bloc.dart';
import 'package:pcos_frontend/features/auth/repository/auth_repository.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late AuthBloc authBloc;
  late MockAuthRepository mockRepo;

  setUp(() {
    mockRepo = MockAuthRepository();
    authBloc = AuthBloc(authRepository: mockRepo);
  });

  tearDown(() => authBloc.close());

  group('AuthBloc', () {
    test('initial state is AuthInitial', () {
      expect(authBloc.state, isA<AuthInitial>());
    });

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthAuthenticated] on successful login',
      build: () {
        when(() => mockRepo.login(
              email: any(named: 'email'),
              password: any(named: 'password'),
            )).thenAnswer((_) async => <String, dynamic>{
              'user': {
                'id': 'test-id',
                'email': 'test@test.com',
                'display_name': 'Test',
              },
              'tokens': {
                'access_token': 'at',
                'refresh_token': 'rt',
              },
            });
        return AuthBloc(authRepository: mockRepo);
      },
      act: (bloc) => bloc.add(
        const AuthLoginRequested(
          email: 'test@test.com',
          password: 'Pass1234',
        ),
      ),
      expect: () => [isA<AuthLoading>(), isA<AuthAuthenticated>()],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthError] on login failure',
      build: () {
        when(() => mockRepo.login(
              email: any(named: 'email'),
              password: any(named: 'password'),
            )).thenThrow(Exception('Invalid credentials'));
        return AuthBloc(authRepository: mockRepo);
      },
      act: (bloc) => bloc.add(
        const AuthLoginRequested(
          email: 'bad@test.com',
          password: 'wrong',
        ),
      ),
      expect: () => [isA<AuthLoading>(), isA<AuthError>()],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthUnauthenticated] on logout',
      build: () {
        when(() => mockRepo.logout()).thenAnswer((_) async {});
        return AuthBloc(authRepository: mockRepo);
      },
      act: (bloc) => bloc.add(const AuthLogoutRequested()),
      expect: () => [isA<AuthUnauthenticated>()],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthUnauthenticated] when no stored session',
      build: () {
        when(() => mockRepo.getCurrentUser()).thenAnswer((_) async => null);
        return AuthBloc(authRepository: mockRepo);
      },
      act: (bloc) => bloc.add(const AuthCheckRequested()),
      expect: () => [isA<AuthUnauthenticated>()],
    );
  });
}
