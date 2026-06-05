import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../models/session.dart';

class FieldApiClient {
  FieldApiClient({String? baseUrl})
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl ?? AppConfig.defaultBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      );

  final Dio _dio;
  FieldSession? _session;

  void setSession(FieldSession? session) {
    _session = session;
  }

  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/auth/login',
      data: {'identifier': identifier, 'password': password},
    );
    return _unwrap(response.data);
  }

  Future<Map<String, dynamic>> getFieldBootstrap() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/field/sync/bootstrap',
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  Future<Map<String, dynamic>> pushLocationPing(
    Map<String, dynamic> data,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/field/location-pings',
      data: data,
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  Options _authOptions() {
    final session = _session;
    return Options(
      headers: {
        if (session != null) 'Authorization': 'Bearer ${session.accessToken}',
        if (session != null) 'X-Org-Id': session.orgId,
      },
    );
  }

  Map<String, dynamic> _unwrap(Map<String, dynamic>? envelope) {
    if (envelope == null) return {};
    final data = envelope['data'];
    if (data is Map<String, dynamic>) return data;
    return envelope;
  }
}
