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

  // ── Auth ──────────────────────────────────────────────────────

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

  Future<Map<String, dynamic>> getMe() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/auth/me',
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  // ── Assignments ───────────────────────────────────────────────

  Future<List<dynamic>> getMyAssignments() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/field-sales/assignments/me',
      options: _authOptions(),
    );
    return _unwrapList(response.data);
  }

  // ── Route Executions ──────────────────────────────────────────

  Future<List<dynamic>> getMyTodayExecutions() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/field-sales/executions/me/today',
      options: _authOptions(),
    );
    return _unwrapList(response.data);
  }

  Future<Map<String, dynamic>> getExecution(String id) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/field-sales/executions/$id',
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  Future<Map<String, dynamic>> startExecution({
    required String routeId,
    required String salespersonId,
    String? vanId,
    required String executionDate,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/field-sales/executions',
      data: {
        'routeId': routeId,
        'salespersonId': salespersonId,
        if (vanId != null) 'vanId': vanId,
        'executionDate': executionDate,
      },
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  Future<Map<String, dynamic>> startRoute(String executionId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/field-sales/executions/$executionId/start',
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  Future<Map<String, dynamic>> completeRoute(String executionId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/field-sales/executions/$executionId/complete',
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  // ── Visits ────────────────────────────────────────────────────

  Future<List<dynamic>> getVisits(String executionId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/field-sales/executions/$executionId/visits',
      options: _authOptions(),
    );
    return _unwrapList(response.data);
  }

  Future<Map<String, dynamic>> checkIn(
    String visitId, {
    required double latitude,
    required double longitude,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/field-sales/visits/$visitId/check-in',
      data: {'latitude': latitude, 'longitude': longitude},
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  Future<Map<String, dynamic>> checkOut(
    String visitId, {
    required double latitude,
    required double longitude,
    String? notes,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/field-sales/visits/$visitId/check-out',
      data: {
        'latitude': latitude,
        'longitude': longitude,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  Future<Map<String, dynamic>> skipVisit(String visitId, String reason) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/field-sales/visits/$visitId/skip',
      data: {'skipReason': reason},
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  Future<Map<String, dynamic>> recordOrder(
    String visitId, {
    required String salesOrderId,
    required double orderValue,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/field-sales/visits/$visitId/record-order',
      data: {'salesOrderId': salesOrderId, 'orderValue': orderValue},
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  Future<Map<String, dynamic>> recordCollection(
    String visitId, {
    required double collectionAmount,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/field-sales/visits/$visitId/record-collection',
      data: {'collectionAmount': collectionAmount},
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  // ── Day Close ─────────────────────────────────────────────────

  Future<Map<String, dynamic>> initiateDayClose(String executionId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/field-sales/day-close/initiate/$executionId',
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  Future<Map<String, dynamic>> submitDayClose(
    String dayCloseId, {
    double? closingCash,
    double? cashDeposited,
    String? notes,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/field-sales/day-close/$dayCloseId/submit',
      data: {
        if (closingCash != null) 'closingCash': closingCash,
        if (cashDeposited != null) 'cashDeposited': cashDeposited,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  Future<Map<String, dynamic>> getDayClose(String id) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/field-sales/day-close/$id',
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  // ── Dashboard ─────────────────────────────────────────────────

  Future<Map<String, dynamic>> getDashboard({
    required String from,
    required String to,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/field-sales/dashboard',
      queryParameters: {'from': from, 'to': to},
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  // ── Targets ───────────────────────────────────────────────────

  Future<List<dynamic>> getMyTargets() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/field-sales/targets/me',
      options: _authOptions(),
    );
    return _unwrapList(response.data);
  }

  // ── Helpers ───────────────────────────────────────────────────

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

  List<dynamic> _unwrapList(Map<String, dynamic>? envelope) {
    if (envelope == null) return [];
    final data = envelope['data'];
    if (data is List) return data;
    final content = (data is Map) ? data['content'] : null;
    if (content is List) return content;
    return [];
  }
}
