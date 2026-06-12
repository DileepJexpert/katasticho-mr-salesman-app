import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/session.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/session_store.dart';

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());
final apiClientProvider = Provider<FieldApiClient>((ref) => FieldApiClient());

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthState {
  const AuthState({this.session, this.isLoading = false, this.error});

  final FieldSession? session;
  final bool isLoading;
  final String? error;

  AuthState copyWith({
    FieldSession? session,
    bool? isLoading,
    String? error,
    bool clearSession = false,
    bool clearError = false,
  }) {
    return AuthState(
      session: clearSession ? null : session ?? this.session,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState(isLoading: true);

  Future<void> load() async {
    final store = ref.read(sessionStoreProvider);
    final api = ref.read(apiClientProvider);
    final session = await store.load();
    api.setSession(session);
    _wireInterceptorCallbacks();
    state = AuthState(session: session);
  }

  Future<void> login(String identifier, String password) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final api = ref.read(apiClientProvider);
      final payload = await api.login(
        identifier: identifier,
        password: password,
      );
      final session = FieldSession.fromAuthPayload(payload);
      await ref.read(sessionStoreProvider).save(session);
      api.setSession(session);
      _wireInterceptorCallbacks();
      state = AuthState(session: session);
    } catch (error) {
      state = AuthState(error: _friendlyError(error));
    }
  }

  /// Connects the API client's token-refresh interceptor to auth state:
  /// a successful background refresh is persisted + reflected in state,
  /// a failed refresh clears the session and returns to the login screen.
  void _wireInterceptorCallbacks() {
    final api = ref.read(apiClientProvider);
    api.onSessionRefreshed = (session) async {
      await ref.read(sessionStoreProvider).save(session);
      state = AuthState(session: session);
    };
    api.onSessionExpired = () async {
      await ref.read(sessionStoreProvider).clear();
      state = const AuthState();
    };
  }

  Future<void> startDemo() async {
    final session = FieldSession.demo();
    await ref.read(sessionStoreProvider).save(session);
    ref.read(apiClientProvider).setSession(session);
    state = AuthState(session: session);
  }

  Future<void> logout() async {
    await ref.read(sessionStoreProvider).clear();
    final api = ref.read(apiClientProvider);
    api.setSession(null);
    api.onSessionRefreshed = null;
    api.onSessionExpired = null;
    state = const AuthState();
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('SocketException') || text.contains('connection')) {
      return 'Backend is not reachable. Check API_BASE_URL and server status.';
    }
    return 'Login failed. Check phone/email and password.';
  }
}
