import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/location/location_ping_tracker.dart';
import '../../core/location/location_service.dart';
import '../../core/storage/offline_queue_provider.dart';
import '../auth/auth_controller.dart';
import '../orders/order_builder_screen.dart';
import '../shared/field_widgets.dart';

class VisitsScreen extends ConsumerStatefulWidget {
  const VisitsScreen({super.key});

  @override
  ConsumerState<VisitsScreen> createState() => _VisitsScreenState();
}

class _VisitsScreenState extends ConsumerState<VisitsScreen> {
  bool _loading = true;
  Map<String, dynamic>? _activeExecution;
  List<Map<String, dynamic>> _visits = [];
  String? _error;
  final _locationService = LocationService();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final session = ref.read(authControllerProvider).session;
    if (session == null || session.isDemo) {
      setState(() => _loading = false);
      return;
    }

    try {
      final api = ref.read(apiClientProvider);
      final executions = await api.getMyTodayExecutions();

      Map<String, dynamic>? active;
      List<Map<String, dynamic>> visits = [];

      if (executions.isNotEmpty) {
        active = executions[0] as Map<String, dynamic>;
        final execId = active['id']?.toString();
        if (execId != null) {
          final rawVisits = await api.getVisits(execId);
          visits = rawVisits.whereType<Map<String, dynamic>>().toList();
        }
      }

      if (mounted) {
        setState(() {
          _activeExecution = active;
          _visits = visits;
        });
        _syncPingTracker(active);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Keeps the GPS breadcrumb tracker aligned with the route state:
  /// pings flow only while a route execution is IN_PROGRESS.
  void _syncPingTracker(Map<String, dynamic>? execution) {
    final tracker = ref.read(locationPingTrackerProvider);
    final execId = execution?['id']?.toString();
    final status = execution?['status']?.toString();
    if (execId != null && status == 'IN_PROGRESS') {
      tracker.start(execId);
    } else {
      tracker.stop();
    }
  }

  Future<void> _startRoute() async {
    final execId = _activeExecution?['id']?.toString();
    if (execId == null) return;

    try {
      await ref.read(apiClientProvider).startRoute(execId);
      _showSuccess('Route started');
      await _loadData();
    } catch (e) {
      _showError('Failed to start route: $e');
    }
  }

  Future<void> _completeRoute() async {
    final execId = _activeExecution?['id']?.toString();
    if (execId == null) return;

    try {
      await ref.read(apiClientProvider).completeRoute(execId);
      _showSuccess('Route completed');
      await _loadData();
    } catch (e) {
      _showError('Failed to complete route: $e');
    }
  }

  Future<void> _checkIn(String visitId) async {
    FieldLocation? loc;
    try {
      loc = await _locationService.currentLocation();
    } catch (_) {
      loc = null;
    }
    final latitude = loc?.latitude ?? 0.0;
    final longitude = loc?.longitude ?? 0.0;

    try {
      final visit = await ref
          .read(apiClientProvider)
          .checkIn(visitId, latitude: latitude, longitude: longitude);
      if (loc == null) _showInfo('Location unavailable — using default');
      if (visit['geoVerified'] == false) {
        final distance =
            (visit['geoDistanceM'] as num?)?.round().toString() ?? '?';
        _showInfo(
          'Note: you are ${distance}m away from this customer\'s '
          'registered location',
        );
      }
      _showSuccess('Checked in');
      await _loadData();
    } catch (e) {
      if (_isNetworkError(e)) {
        await _enqueueAction(
          'CHECK_IN',
          '/api/v1/field-sales/visits/$visitId/check-in',
          {'latitude': latitude, 'longitude': longitude},
        );
      } else {
        _showError('Check-in failed: $e');
      }
    }
  }

  Future<void> _checkOut(String visitId) async {
    final notesCtl = TextEditingController();
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Check Out'),
        content: TextField(
          controller: notesCtl,
          decoration: const InputDecoration(
            labelText: 'Notes',
            hintText: 'Visit remarks (optional)',
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Check Out'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    FieldLocation? loc;
    try {
      loc = await _locationService.currentLocation();
    } catch (_) {
      loc = null;
    }
    final latitude = loc?.latitude ?? 0.0;
    final longitude = loc?.longitude ?? 0.0;
    final notes = notesCtl.text.trim();

    try {
      await ref
          .read(apiClientProvider)
          .checkOut(
            visitId,
            latitude: latitude,
            longitude: longitude,
            notes: notes.isNotEmpty ? notes : null,
          );
      _showSuccess('Checked out');
      await _loadData();
    } catch (e) {
      if (_isNetworkError(e)) {
        await _enqueueAction(
          'CHECK_OUT',
          '/api/v1/field-sales/visits/$visitId/check-out',
          {
            'latitude': latitude,
            'longitude': longitude,
            if (notes.isNotEmpty) 'notes': notes,
          },
        );
      } else {
        _showError('Check-out failed: $e');
      }
    }
  }

  Future<void> _skipVisit(String visitId) async {
    final reasonCtl = TextEditingController();
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Skip Visit'),
        content: TextField(
          controller: reasonCtl,
          decoration: const InputDecoration(
            labelText: 'Reason *',
            hintText: 'e.g. Shop closed, owner unavailable',
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (reasonCtl.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Reason is required')),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Skip'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    try {
      await ref
          .read(apiClientProvider)
          .skipVisit(visitId, reasonCtl.text.trim());
      _showSuccess('Visit skipped');
      await _loadData();
    } catch (e) {
      _showError('Failed to skip: $e');
    }
  }

  /// Record Order entry point: bottom sheet with two paths —
  /// build a real line-item Sales Order, or the quick-amount dialog
  /// (which stays offline-capable).
  Future<void> _showOrderOptions(Map<String, dynamic> visit) async {
    final visitId = visit['id']?.toString() ?? '';
    final contactId = visit['contactId']?.toString() ?? '';
    final contactName =
        visit['contactName']?.toString() ??
        visit['contactId']?.toString() ??
        'Customer';

    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Build order (items)'),
              subtitle: const Text(
                'Browse catalog, build a cart, create a Sales Order',
              ),
              onTap: () => Navigator.pop(ctx, 'build'),
            ),
            ListTile(
              leading: const Icon(Icons.currency_rupee),
              title: const Text('Quick amount'),
              subtitle: const Text(
                'Just record the order value (works offline)',
              ),
              onTap: () => Navigator.pop(ctx, 'quick'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'build') {
      final placed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => OrderBuilderScreen(
            visitId: visitId,
            contactId: contactId,
            contactName: contactName,
          ),
        ),
      );
      if (placed == true && mounted) await _loadData();
    } else {
      await _recordOrder(visitId);
    }
  }

  Future<void> _recordOrder(String visitId) async {
    final valueCtl = TextEditingController();
    final soIdCtl = TextEditingController();
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record Order'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: soIdCtl,
              decoration: const InputDecoration(
                labelText: 'Sales Order ID',
                hintText: 'Optional',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: valueCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Order Value *',
                hintText: 'e.g. 5000',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (valueCtl.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Order value is required')),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Record'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    final salesOrderId = soIdCtl.text.trim();
    final orderValue = double.tryParse(valueCtl.text.trim()) ?? 0;

    try {
      await ref
          .read(apiClientProvider)
          .recordOrder(visitId, salesOrderId: salesOrderId, orderValue: orderValue);
      _showSuccess('Order recorded');
      await _loadData();
    } catch (e) {
      if (_isNetworkError(e)) {
        await _enqueueAction(
          'RECORD_ORDER',
          '/api/v1/field-sales/visits/$visitId/record-order',
          {'salesOrderId': salesOrderId, 'orderValue': orderValue},
        );
      } else {
        _showError('Failed to record order: $e');
      }
    }
  }

  Future<void> _recordCollection(String visitId) async {
    final amountCtl = TextEditingController();
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record Collection'),
        content: TextField(
          controller: amountCtl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Amount *',
            hintText: 'e.g. 2500',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (amountCtl.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Amount is required')),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Record'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    final collectionAmount = double.tryParse(amountCtl.text.trim()) ?? 0;

    try {
      await ref
          .read(apiClientProvider)
          .recordCollection(visitId, collectionAmount: collectionAmount);
      _showSuccess('Collection recorded');
      await _loadData();
    } catch (e) {
      if (_isNetworkError(e)) {
        await _enqueueAction(
          'RECORD_COLLECTION',
          '/api/v1/field-sales/visits/$visitId/record-collection',
          {'collectionAmount': collectionAmount},
        );
      } else {
        _showError('Failed to record collection: $e');
      }
    }
  }

  /// Captures Proof of Delivery for a delivered shipment — recipient +
  /// GPS + deliveredAt, linked to a delivery challan or invoice. Auto-
  /// stamps the salesperson's current GPS and `deliveredAt = now`.
  Future<void> _recordPod(Map<String, dynamic> visit) async {
    final form = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RecordPodSheet(
        contactName: visit['contactName']?.toString(),
      ),
    );
    if (form == null || !mounted) return;

    FieldLocation? loc;
    try {
      loc = await _locationService.currentLocation();
    } catch (_) {
      loc = null;
    }
    final now = DateTime.now().toUtc().toIso8601String();

    final body = <String, dynamic>{
      ...form,
      'deliveredAt': now,
      if (loc != null) 'geoLatitude': loc.latitude,
      if (loc != null) 'geoLongitude': loc.longitude,
    };

    try {
      await ref.read(apiClientProvider).recordPod(body);
      _showSuccess('Proof of delivery recorded');
    } catch (e) {
      if (_isNetworkError(e)) {
        await _enqueueAction('RECORD_POD', '/api/v1/proof-of-delivery', body);
      } else {
        _showError('Failed to record POD: $e');
      }
    }
  }

  // ── Offline support ───────────────────────────────────────────

  /// True when the failure is connectivity-related (worth queuing
  /// offline) rather than a server-side rejection.
  bool _isNetworkError(Object e) {
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return true;
        default:
          break;
      }
    }
    final text = e.toString();
    return text.contains('SocketException') ||
        text.contains('Connection refused') ||
        text.contains('Network is unreachable') ||
        text.contains('Failed host lookup');
  }

  Future<void> _enqueueAction(
    String type,
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    await ref
        .read(offlineQueueProvider)
        .enqueue(type: type, endpoint: endpoint, body: body);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saved offline — will sync when connected'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// MR detailing sheet: which products were detailed, samples and
  /// gifts given during this visit. Feeds the day's DCR summary.
  Future<void> _logDetailing(String visitId) async {
    List<Map<String, dynamic>> rows = [];
    try {
      final existing =
          await ref.read(apiClientProvider).getVisitProducts(visitId);
      rows = existing
          .whereType<Map>()
          .map((e) => <String, dynamic>{
                'productName': e['productName']?.toString() ?? '',
                'sampleQty': (e['sampleQty'] as num?)?.toInt() ?? 0,
                'giftName': e['giftName']?.toString() ?? '',
              })
          .toList();
    } catch (_) {
      // start empty when offline / first time
    }
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _DetailingSheet(visitId: visitId, initialRows: rows),
      ),
    );
  }

  /// E-detailing: pick and open brochures/visual aids during the visit;
  /// the selection is logged against the visit for coverage analytics.
  Future<void> _showAids(String visitId) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AidsSheet(visitId: visitId),
    );
  }

  void _showInfo(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).session;
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (session?.isDemo == true) {
      return const PageScaffold(
        title: 'Visits',
        subtitle: 'Demo mode — login to see real visits.',
        children: [],
      );
    }

    final execStatus = _activeExecution?['status']?.toString() ?? 'NONE';

    return RefreshIndicator(
      onRefresh: _loadData,
      child: PageScaffold(
        title: 'Visits',
        subtitle: 'Geo-verified check-ins. GPS captured on every check-in/out.',
        children: [
          if (_error != null) ...[
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _error!,
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Route status bar
          if (_activeExecution != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _activeExecution!['routeName']?.toString() ??
                                'Today\'s Route',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Status: ${execStatus.replaceAll('_', ' ')}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (execStatus == 'PLANNED')
                      FilledButton(
                        onPressed: _startRoute,
                        child: const Text('Start'),
                      ),
                    if (execStatus == 'IN_PROGRESS')
                      FilledButton(
                        onPressed: _completeRoute,
                        child: const Text('Complete'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ] else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.event_busy, color: Colors.grey.shade400),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('No route execution for today.'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Visits list
          if (_visits.isEmpty && _activeExecution != null)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text('No visits in this route.'),
              ),
            )
          else
            ..._visits.map((visit) => _buildVisitCard(visit, theme)),
        ],
      ),
    );
  }

  Widget _buildVisitCard(Map<String, dynamic> visit, ThemeData theme) {
    final visitId = visit['id']?.toString() ?? '';
    final status = visit['status']?.toString() ?? 'PLANNED';
    final contactName =
        visit['contactName']?.toString() ??
        visit['contactId']?.toString() ??
        'Customer';
    final seq =
        (visit['sequence'] as num?)?.toInt() ??
        (visit['sequenceNumber'] as num?)?.toInt();
    final checkInTime = visit['checkInTime']?.toString();
    final checkOutTime = visit['checkOutTime']?.toString();
    final orderValue = (visit['orderValue'] as num?)?.toDouble();
    final collectionAmount = (visit['collectionAmount'] as num?)?.toDouble();
    final skipReason = visit['skipReason']?.toString();

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'IN_PROGRESS':
        statusColor = Colors.orange;
        statusLabel = 'In Visit';
      case 'COMPLETED':
        statusColor = Colors.green;
        statusLabel = 'Done';
      case 'SKIPPED':
        statusColor = Colors.red;
        statusLabel = 'Skipped';
      default:
        statusColor = Colors.blue;
        statusLabel = 'Planned';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (seq != null) ...[
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: statusColor.withValues(alpha: 0.15),
                    child: Text(
                      '$seq',
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    contactName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  backgroundColor: statusColor.withValues(alpha: 0.1),
                  side: BorderSide.none,
                ),
              ],
            ),

            if (checkInTime != null) ...[
              const SizedBox(height: 6),
              Text('Check-in: $checkInTime', style: theme.textTheme.bodySmall),
            ],
            if (checkOutTime != null)
              Text(
                'Check-out: $checkOutTime',
                style: theme.textTheme.bodySmall,
              ),
            if (orderValue != null && orderValue > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Order: ₹${orderValue.toStringAsFixed(0)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (collectionAmount != null && collectionAmount > 0)
              Text(
                'Collection: ₹${collectionAmount.toStringAsFixed(0)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (status == 'SKIPPED' && skipReason != null) ...[
              const SizedBox(height: 4),
              Text(
                'Reason: $skipReason',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
              ),
            ],

            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (status == 'PLANNED') ...[
                  FilledButton.icon(
                    onPressed: () => _checkIn(visitId),
                    icon: const Icon(Icons.location_on, size: 18),
                    label: const Text('Check In'),
                  ),
                  OutlinedButton(
                    onPressed: () => _skipVisit(visitId),
                    child: const Text('Skip'),
                  ),
                ],
                if (status == 'IN_PROGRESS') ...[
                  FilledButton.icon(
                    onPressed: () => _checkOut(visitId),
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Check Out'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _showOrderOptions(visit),
                    icon: const Icon(Icons.shopping_cart, size: 18),
                    label: const Text('Order'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _recordCollection(visitId),
                    icon: const Icon(Icons.payments, size: 18),
                    label: const Text('Collect'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _logDetailing(visitId),
                    icon: const Icon(Icons.medication, size: 18),
                    label: const Text('Detail'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _showAids(visitId),
                    icon: const Icon(Icons.auto_stories, size: 18),
                    label: const Text('Aids'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _recordPod(visit),
                    icon: const Icon(Icons.assignment_turned_in, size: 18),
                    label: const Text('POD'),
                  ),
                ],
                if (status == 'COMPLETED') ...[
                  OutlinedButton.icon(
                    onPressed: () => _showOrderOptions(visit),
                    icon: const Icon(Icons.shopping_cart, size: 18),
                    label: const Text('Order'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _recordCollection(visitId),
                    icon: const Icon(Icons.payments, size: 18),
                    label: const Text('Collect'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _logDetailing(visitId),
                    icon: const Icon(Icons.medication, size: 18),
                    label: const Text('Detail'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _recordPod(visit),
                    icon: const Icon(Icons.assignment_turned_in, size: 18),
                    label: const Text('POD'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet for recording products detailed + samples/gifts on a visit.
class _DetailingSheet extends ConsumerStatefulWidget {
  const _DetailingSheet({required this.visitId, required this.initialRows});

  final String visitId;
  final List<Map<String, dynamic>> initialRows;

  @override
  ConsumerState<_DetailingSheet> createState() => _DetailingSheetState();
}

class _DetailingSheetState extends ConsumerState<_DetailingSheet> {
  late List<Map<String, dynamic>> _rows;
  final _productCtl = TextEditingController();
  final _samplesCtl = TextEditingController(text: '0');
  final _giftCtl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _rows = List.of(widget.initialRows);
  }

  @override
  void dispose() {
    _productCtl.dispose();
    _samplesCtl.dispose();
    _giftCtl.dispose();
    super.dispose();
  }

  void _addRow() {
    final name = _productCtl.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _rows.add({
        'productName': name,
        'sampleQty': int.tryParse(_samplesCtl.text) ?? 0,
        'giftName': _giftCtl.text.trim(),
      });
      _productCtl.clear();
      _samplesCtl.text = '0';
      _giftCtl.clear();
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).logVisitProducts(
            widget.visitId,
            _rows
                .map((r) => {
                      'productName': r['productName'],
                      'detailed': true,
                      'sampleQty': r['sampleQty'] ?? 0,
                      if ((r['giftName'] as String?)?.isNotEmpty ?? false)
                        'giftName': r['giftName'],
                      if ((r['giftName'] as String?)?.isNotEmpty ?? false)
                        'giftQty': 1,
                    })
                .toList(),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save detailing: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Detailing & Samples',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ..._rows.asMap().entries.map((entry) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.medication_outlined),
                  title: Text(entry.value['productName']?.toString() ?? ''),
                  subtitle: Text(
                      'Samples: ${entry.value['sampleQty'] ?? 0}'
                      '${(entry.value['giftName'] as String?)?.isNotEmpty ?? false ? " • Gift: ${entry.value['giftName']}" : ""}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () =>
                        setState(() => _rows.removeAt(entry.key)),
                  ),
                )),
            const Divider(),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _productCtl,
                    decoration:
                        const InputDecoration(labelText: 'Product detailed'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _samplesCtl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Samples'),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _giftCtl,
                    decoration:
                        const InputDecoration(labelText: 'Gift (optional)'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _addRow,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save),
                label: Text(_saving ? 'Saving…' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet: active detail aids with open-link + shown checkboxes.
class _AidsSheet extends ConsumerStatefulWidget {
  const _AidsSheet({required this.visitId});

  final String visitId;

  @override
  ConsumerState<_AidsSheet> createState() => _AidsSheetState();
}

class _AidsSheetState extends ConsumerState<_AidsSheet> {
  List<Map<String, dynamic>> _aids = [];
  final Set<String> _shown = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(apiClientProvider);
      final aids = await api.getDetailAids();
      final log = await api.getVisitDetailAids(widget.visitId);
      if (mounted) {
        setState(() {
          _aids = aids.whereType<Map<String, dynamic>>().toList();
          _shown.addAll(log
              .whereType<Map>()
              .map((e) => e['detailAidId']?.toString() ?? '')
              .where((id) => id.isNotEmpty));
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Map<String, dynamic> aid) async {
    final url = aid['mediaUrl']?.toString();
    if (url == null || url.isEmpty) return;
    setState(() => _shown.add(aid['id'].toString()));
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(apiClientProvider)
          .logVisitDetailAids(widget.visitId, _shown.toList());
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save aids: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Detail aids',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('Open to present; tick what you showed.',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  if (_aids.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No detail aids published yet — ask your '
                          'admin to add brochures in the ERP.'),
                    ),
                  ..._aids.map((aid) {
                    final id = aid['id'].toString();
                    return CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _shown.contains(id),
                      onChanged: (v) => setState(() =>
                          v == true ? _shown.add(id) : _shown.remove(id)),
                      title: Text(aid['name']?.toString() ?? ''),
                      subtitle: aid['productName'] != null
                          ? Text(aid['productName'].toString())
                          : null,
                      secondary: IconButton(
                        icon: const Icon(Icons.open_in_new),
                        tooltip: 'Open',
                        onPressed: () => _open(aid),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving || _aids.isEmpty ? null : _save,
                      icon: const Icon(Icons.save),
                      label: Text(_saving ? 'Saving…' : 'Save'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}


/// Bottom-sheet form for capturing Proof of Delivery from a visit.
///
/// Caller composes the body — recipient + DC/invoice link — and the
/// parent screen stamps deliveredAt + GPS before posting. Kept JSON-only
/// for now; photo / signature attachments can be wired up once
/// image_picker is added to the field-app pubspec.
class _RecordPodSheet extends StatefulWidget {
  const _RecordPodSheet({this.contactName});

  /// Pre-filled hint shown above the form so the salesperson knows which
  /// customer they're capturing for.
  final String? contactName;

  @override
  State<_RecordPodSheet> createState() => _RecordPodSheetState();
}

class _RecordPodSheetState extends State<_RecordPodSheet> {
  final _challanId = TextEditingController();
  final _invoiceId = TextEditingController();
  final _recipient = TextEditingController();
  final _phone = TextEditingController();
  final _relation = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _challanId.dispose();
    _invoiceId.dispose();
    _recipient.dispose();
    _phone.dispose();
    _relation.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _ready =>
      _recipient.text.trim().isNotEmpty &&
      (_challanId.text.trim().isNotEmpty ||
          _invoiceId.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + inset),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Record Proof of Delivery",
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (widget.contactName != null) ...[
                const SizedBox(height: 4),
                Text(
                  "For ${widget.contactName}",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                "Link to either a delivery challan or an invoice.",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              TextField(
                controller: _challanId,
                decoration: const InputDecoration(
                  labelText: "Delivery challan id",
                ),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                controller: _invoiceId,
                decoration: const InputDecoration(labelText: "Invoice id"),
                onChanged: (_) => setState(() {}),
              ),
              const Divider(height: 24),
              TextField(
                controller: _recipient,
                decoration: const InputDecoration(
                  labelText: "Recipient name *",
                ),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                controller: _phone,
                decoration: const InputDecoration(labelText: "Phone"),
                keyboardType: TextInputType.phone,
              ),
              TextField(
                controller: _relation,
                decoration: const InputDecoration(
                  labelText: "Relationship (Self / Watchman / …)",
                ),
              ),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(labelText: "Notes"),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              const Text(
                "GPS and timestamp will be stamped automatically.",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Cancel"),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: !_ready
                        ? null
                        : () => Navigator.pop(context, {
                            if (_challanId.text.trim().isNotEmpty)
                              "deliveryChallanId": _challanId.text.trim(),
                            if (_invoiceId.text.trim().isNotEmpty)
                              "invoiceId": _invoiceId.text.trim(),
                            "recipientName": _recipient.text.trim(),
                            if (_phone.text.trim().isNotEmpty)
                              "recipientPhone": _phone.text.trim(),
                            if (_relation.text.trim().isNotEmpty)
                              "recipientRelation": _relation.text.trim(),
                            if (_notes.text.trim().isNotEmpty)
                              "notes": _notes.text.trim(),
                          }),
                    child: const Text("Save"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
