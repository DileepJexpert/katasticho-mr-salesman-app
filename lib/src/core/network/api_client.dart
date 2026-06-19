import 'dart:async';

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
      ) {
    _dio.interceptors.add(_TokenRefreshInterceptor(this));
  }

  final Dio _dio;
  FieldSession? _session;

  /// Invoked after a successful background token refresh so the app can
  /// persist the new session (SessionStore) and update auth state.
  void Function(FieldSession session)? onSessionRefreshed;

  /// Invoked when a token refresh fails — the session is no longer usable
  /// and the user should be sent back to the login screen.
  void Function()? onSessionExpired;

  FieldSession? get session => _session;

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

  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/auth/refresh',
      data: {'refreshToken': refreshToken},
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

  /// Records a Proof of Delivery against a delivery challan and/or invoice.
  /// Mirrors the ERP `ProofOfDeliveryController.record` endpoint. The body
  /// is whatever the caller composed (POD_LINK_REQUIRED is enforced on the
  /// server). Used by the visit-action "POD" button.
  Future<Map<String, dynamic>> recordPod(Map<String, dynamic> body) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/proof-of-delivery',
      data: body,
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

  // ── Contacts (Parties) ────────────────────────────────────────

  /// GET /api/v1/contacts — paged (Spring Page); returns `data.content`.
  /// [type] filters by contact type: CUSTOMER / VENDOR / BOTH.
  Future<List<dynamic>> getContacts({String? search, String? type}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/contacts',
      queryParameters: {
        if (search != null && search.isNotEmpty) 'search': search,
        if (type != null && type.isNotEmpty) 'type': type,
        'size': 50,
      },
      options: _authOptions(),
    );
    return _unwrapList(response.data);
  }

  Future<Map<String, dynamic>> getContact(String id) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/contacts/$id',
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  // ── Expenses ──────────────────────────────────────────────────

  /// GET /api/v1/expenses — paged response; returns `data.content`.
  /// [from] / [to] are ISO dates (yyyy-MM-dd).
  Future<List<dynamic>> getExpenses({String? from, String? to}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/expenses',
      queryParameters: {
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        'size': 50,
      },
      options: _authOptions(),
    );
    return _unwrapList(response.data);
  }

  /// POST /api/v1/expenses — requires expenseDate, accountId (expense
  /// account), amount, paymentMode, paidThroughId (cash/bank account).
  Future<Map<String, dynamic>> createExpense({
    required String expenseDate,
    required String accountId,
    required double amount,
    required String paymentMode,
    required String paidThroughId,
    String? category,
    String? description,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/expenses',
      data: {
        'expenseDate': expenseDate,
        'accountId': accountId,
        'amount': amount,
        'paymentMode': paymentMode,
        'paidThroughId': paidThroughId,
        if (category != null && category.isNotEmpty) 'category': category,
        if (description != null && description.isNotEmpty)
          'description': description,
      },
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  // ── Chart of Accounts ─────────────────────────────────────────

  /// GET /api/v1/accounts — flat list used to resolve the expense
  /// account and the cash (paid-through) account for expense entry.
  Future<List<dynamic>> getAccounts() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/accounts',
      options: _authOptions(),
    );
    return _unwrapList(response.data);
  }

  // ── Catalog & Sales Orders ────────────────────────────────────

  /// GET /api/v1/items — paged (Spring Page); returns `data.content`.
  /// Each item: id, sku, name, salePrice, mrp, gstRate, defaultTaxGroupId,
  /// unitOfMeasure, hsnCode, totalOnHand, trackInventory.
  Future<List<dynamic>> searchItems(String query) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/items',
      queryParameters: {
        if (query.isNotEmpty) 'search': query,
        'size': 10,
        'activeOnly': true,
      },
      options: _authOptions(),
    );
    return _unwrapList(response.data);
  }

  /// POST /api/v1/sales-orders — creates a real Sales Order.
  /// Lines: [{'itemId', 'description', 'quantity', 'rate', 'discountPct',
  /// 'taxGroupId'?, 'hsnCode'?}]. Returns the full SO map including
  /// `id`, `salesOrderNumber`, `totalAmount`, `status` and `warnings`
  /// (warnings arrive AFTER the SO has been created — informational only).
  Future<Map<String, dynamic>> createSalesOrder({
    required String contactId,
    required List<Map<String, dynamic>> lines,
    String? notes,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/sales-orders',
      data: {
        'contactId': contactId,
        'lines': lines,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  // ── Van Stock ─────────────────────────────────────────────────

  Future<List<dynamic>> getVanStock(String vanId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/field-sales/vans/$vanId/stock',
      options: _authOptions(),
    );
    return _unwrapList(response.data);
  }

  /// Creates a DRAFT van load transfer.
  /// Lines: [{'itemId': uuid, 'quantity': num, 'batchId'?: uuid}]
  Future<Map<String, dynamic>> createVanLoad(
    String vanId,
    String warehouseId,
    List<Map<String, dynamic>> lines,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/field-sales/van-transfers/load',
      data: {'vanId': vanId, 'warehouseId': warehouseId, 'lines': lines},
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  Future<Map<String, dynamic>> confirmVanLoad(String transferId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/field-sales/van-transfers/$transferId/confirm-load',
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  /// Creates a DRAFT van return transfer.
  Future<Map<String, dynamic>> createVanReturn(
    String vanId,
    String warehouseId,
    List<Map<String, dynamic>> lines, {
    String? routeExecutionId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/field-sales/van-transfers/return',
      data: {
        'vanId': vanId,
        'warehouseId': warehouseId,
        if (routeExecutionId != null) 'routeExecutionId': routeExecutionId,
        'lines': lines,
      },
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  Future<Map<String, dynamic>> confirmVanReturn(String transferId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/field-sales/van-transfers/$transferId/confirm-return',
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  Future<List<dynamic>> getVanTransfers(String vanId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/field-sales/van-transfers/van/$vanId',
      options: _authOptions(),
    );
    return _unwrapList(response.data);
  }

  Future<List<dynamic>> getTransferLines(String transferId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/field-sales/van-transfers/$transferId/lines',
      options: _authOptions(),
    );
    return _unwrapList(response.data);
  }

  // ── MR reporting: tour plans + DCR ───────────────────────────

  Future<Map<String, dynamic>> createTourPlan(
    String planMonth, {
    String? notes,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/mr/tour-plans',
      data: {
        'planMonth': planMonth,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  Future<List<dynamic>> getMyTourPlans() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/mr/tour-plans/me',
      options: _authOptions(),
    );
    return _unwrapList(response.data);
  }

  Future<Map<String, dynamic>> getTourPlan(String id) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/mr/tour-plans/$id',
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  Future<Map<String, dynamic>> addTourPlanEntry(
    String planId,
    Map<String, dynamic> entry,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/mr/tour-plans/$planId/entries',
      data: entry,
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  Future<void> removeTourPlanEntry(String entryId) async {
    await _dio.delete<Map<String, dynamic>>(
      '/api/v1/mr/tour-plans/entries/$entryId',
      options: _authOptions(),
    );
  }

  Future<Map<String, dynamic>> submitTourPlan(String planId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/mr/tour-plans/$planId/submit',
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  Future<Map<String, dynamic>> buildDcr({String? date}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/mr/dcr/build',
      data: {if (date != null) 'date': date},
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  Future<Map<String, dynamic>> submitDcr({
    String? date,
    String? workType,
    String? remarks,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/mr/dcr/submit',
      data: {
        if (date != null) 'date': date,
        if (workType != null) 'workType': workType,
        if (remarks != null && remarks.isNotEmpty) 'remarks': remarks,
      },
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  Future<List<dynamic>> getMyDcrs() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/mr/dcr/me',
      options: _authOptions(),
    );
    return _unwrapList(response.data);
  }

  Future<List<dynamic>> logVisitProducts(
    String visitId,
    List<Map<String, dynamic>> products,
  ) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/api/v1/mr/visits/$visitId/products',
      data: {'products': products},
      options: _authOptions(),
    );
    return _unwrapList(response.data);
  }

  Future<List<dynamic>> getVisitProducts(String visitId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/mr/visits/$visitId/products',
      options: _authOptions(),
    );
    return _unwrapList(response.data);
  }

  // ── Detail aids (e-detailing) ─────────────────────────────────

  Future<List<dynamic>> getDetailAids() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/mr/detail-aids',
      options: _authOptions(),
    );
    return _unwrapList(response.data);
  }

  Future<List<dynamic>> getVisitDetailAids(String visitId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/mr/visits/$visitId/detail-aids',
      options: _authOptions(),
    );
    return _unwrapList(response.data);
  }

  Future<List<dynamic>> logVisitDetailAids(
    String visitId,
    List<String> aidIds,
  ) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/api/v1/mr/visits/$visitId/detail-aids',
      data: {'aidIds': aidIds},
      options: _authOptions(),
    );
    return _unwrapList(response.data);
  }

  // ── Attendance + leave ────────────────────────────────────────

  Future<Map<String, dynamic>?> getAttendanceToday() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/attendance/today',
      options: _authOptions(),
    );
    final data = response.data?['data'];
    return data is Map ? data.cast<String, dynamic>() : null;
  }

  Future<Map<String, dynamic>> punchIn({
    double? latitude,
    double? longitude,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/attendance/punch-in',
      data: {
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      },
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  Future<Map<String, dynamic>> punchOut({
    double? latitude,
    double? longitude,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/attendance/punch-out',
      data: {
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      },
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  Future<Map<String, dynamic>> applyLeave({
    required String fromDate,
    required String toDate,
    required String leaveType,
    String? reason,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/attendance/leave',
      data: {
        'fromDate': fromDate,
        'toDate': toDate,
        'leaveType': leaveType,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  Future<List<dynamic>> getMyLeaves() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/attendance/leave/me',
      options: _authOptions(),
    );
    return _unwrapList(response.data);
  }

  // ── Allowance + samples (all verticals) ───────────────────────

  Future<Map<String, dynamic>> getMyAllowance({String? date}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/field-sales/allowance/me',
      queryParameters: {if (date != null) 'date': date},
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  Future<Map<String, dynamic>> claimAllowance({String? date, double? km}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/field-sales/allowance/claim',
      data: {
        if (date != null) 'date': date,
        if (km != null) 'km': km,
      },
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  Future<List<dynamic>> getMySampleBalance() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/field-sales/samples/balance/me',
      options: _authOptions(),
    );
    return _unwrapList(response.data);
  }

  // ── Location tracking ─────────────────────────────────────────

  /// Sends a batch of GPS breadcrumb pings. Each ping: latitude,
  /// longitude, accuracyM, recordedAt (ISO-8601), routeExecutionId.
  Future<Map<String, dynamic>> sendLocationPings(
    List<Map<String, dynamic>> pings,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/field-sales/locations/ping',
      data: {'pings': pings},
      options: _authOptions(),
    );
    return _unwrap(response.data);
  }

  // ── Offline replay ────────────────────────────────────────────

  /// Generic authenticated POST used by the offline queue to replay
  /// queued actions against their original endpoint + body.
  Future<Map<String, dynamic>> rawPost(
    String path,
    Map<String, dynamic> data,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      path,
      data: data,
      options: _authOptions(),
    );
    return _unwrap(response.data);
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

/// Transparent 401 → refresh → retry interceptor.
///
/// On a 401 from any authenticated call it refreshes the access token via
/// `POST /api/v1/auth/refresh` (serialized through a shared [Completer] so
/// concurrent 401s trigger exactly one refresh), updates the client session,
/// notifies [FieldApiClient.onSessionRefreshed], and replays the original
/// request. If the refresh itself fails, [FieldApiClient.onSessionExpired]
/// fires so the app can drop back to the login screen.
class _TokenRefreshInterceptor extends Interceptor {
  _TokenRefreshInterceptor(this._client);

  final FieldApiClient _client;
  Completer<bool>? _refreshCompleter;

  static const _skippedPaths = ['/api/v1/auth/login', '/api/v1/auth/refresh'];

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final status = err.response?.statusCode;
    final path = err.requestOptions.path;
    final session = _client.session;

    final shouldAttempt =
        status == 401 &&
        session != null &&
        !session.isDemo &&
        session.refreshToken.isNotEmpty &&
        !_skippedPaths.any(path.contains);

    if (!shouldAttempt) {
      handler.next(err);
      return;
    }

    final refreshed = await _refresh();
    if (!refreshed) {
      handler.next(err);
      return;
    }

    // Replay the original request with the fresh token.
    final fresh = _client.session;
    if (fresh == null) {
      handler.next(err);
      return;
    }
    final options = err.requestOptions;
    options.headers['Authorization'] = 'Bearer ${fresh.accessToken}';
    options.headers['X-Org-Id'] = fresh.orgId;
    try {
      final response = await _client._dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    } catch (_) {
      handler.next(err);
    }
  }

  Future<bool> _refresh() async {
    final inFlight = _refreshCompleter;
    if (inFlight != null) return inFlight.future;

    final completer = Completer<bool>();
    _refreshCompleter = completer;
    try {
      final current = _client.session;
      if (current == null || current.refreshToken.isEmpty) {
        completer.complete(false);
      } else {
        final payload = await _client.refreshToken(current.refreshToken);
        final next = FieldSession.fromAuthPayload(payload);
        if (next.accessToken.isEmpty) {
          throw StateError('Refresh response missing accessToken');
        }
        _client.setSession(next);
        _client.onSessionRefreshed?.call(next);
        completer.complete(true);
      }
    } catch (_) {
      _client.setSession(null);
      _client.onSessionExpired?.call();
      completer.complete(false);
    } finally {
      _refreshCompleter = null;
    }
    return completer.future;
  }
}
