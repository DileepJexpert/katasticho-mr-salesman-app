import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/location/location_ping_tracker.dart';
import '../../core/location/location_service.dart';
import '../../core/storage/offline_queue_provider.dart';
import '../auth/auth_controller.dart';
import '../mr/rcpa_sheet.dart';
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
  List<Map<String, dynamic>> _assignments = [];
  Map<String, dynamic>? _attendance;
  String? _error;
  String _selectedStopFilter = 'ALL';
  final _locationService = LocationService();
  final Set<String> _inFlightCheckIns = {};

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
      List<Map<String, dynamic>> assignments = [];

      Map<String, Map<String, dynamic>> contactMap = {};
      try {
        final rawContacts = await api.getContacts();
        for (final c in rawContacts) {
          if (c is Map) {
            final cid = c['id']?.toString();
            if (cid != null) {
              contactMap[cid] = Map<String, dynamic>.from(c);
            }
          }
        }
      } catch (_) {}

      Map<String, dynamic>? attendance;
      try {
        attendance = await api.getAttendanceToday();
      } catch (_) {}

      if (executions.isNotEmpty) {
        active = executions[0] as Map<String, dynamic>;
        final execId = active['id']?.toString();
        if (execId != null) {
          final rawVisits = await api.getVisits(execId);
          visits = rawVisits
              .whereType<Map>()
              .map((v) => Map<String, dynamic>.from(v))
              .toList();

          for (final v in visits) {
            final cid = v['contactId']?.toString();
            if (cid != null && contactMap.containsKey(cid)) {
              final c = contactMap[cid]!;
              v['contactName'] ??= c['displayName'];
              v['contactPhone'] ??= c['phone'];
              v['medicalCategory'] ??= c['medicalCategory'];
              v['city'] ??= c['billingCity'];
              v['address'] ??= [c['billingAddressLine1'], c['billingCity']]
                  .where((x) => x != null && x.toString().isNotEmpty)
                  .join(', ');
              v['outstandingAr'] ??= (c['outstandingAr'] as num?)?.toDouble();
              v['latitude'] ??= (c['latitude'] as num?)?.toDouble();
              v['longitude'] ??= (c['longitude'] as num?)?.toDouble();
            }
          }
        }
      } else {
        try {
          final raw = await api.getMyAssignments();
          assignments = raw
              .whereType<Map>()
              .map((a) => Map<String, dynamic>.from(a))
              .toList();
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _activeExecution = active;
          _visits = visits;
          _assignments = assignments;
          _attendance = attendance;
        });
        _syncPingTracker(active);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _punchTime(String? iso) {
    final t = iso != null ? DateTime.tryParse(iso)?.toLocal() : null;
    if (t == null) return '--:--';
    final period = t.hour >= 12 ? 'PM' : 'AM';
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  Future<void> _punch({required bool isIn}) async {
    FieldLocation? loc;
    try {
      loc = await _locationService.currentLocation();
    } catch (_) {}
    try {
      final api = ref.read(apiClientProvider);
      if (isIn) {
        await api.punchIn(latitude: loc?.latitude, longitude: loc?.longitude);
        _showSuccess('Punched In — Duty started!');
      } else {
        await api.punchOut(latitude: loc?.latitude, longitude: loc?.longitude);
        _showSuccess('Punched Out — Shift ended!');
      }
      await _loadData();
    } catch (e) {
      _showError('Punch failed: $e');
    }
  }

  void _callContact(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (clean.isEmpty) return;
    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showError('Cannot launch dialer for $phone');
    }
  }

  void _whatsappContact(String phone, String name) async {
    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return;
    final numWithCountry = digits.length == 10 ? '91$digits' : digits;
    final text = Uri.encodeComponent(
      'Hello $name, this is ${ref.read(authControllerProvider).session?.fullName ?? 'your Field Rep'} from Moonford Pharmaceuticals.',
    );
    final uri = Uri.parse('https://wa.me/$numWithCountry?text=$text');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _openMapDirections(String name, String address, String city) async {
    final query = [name, if (address.isNotEmpty) address, if (city.isNotEmpty) city].join(', ');
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  List<Map<String, dynamic>> get _filteredVisits {
    if (_selectedStopFilter == 'ALL') return _visits;
    if (_selectedStopFilter == 'DOCTOR') {
      return _visits.where((v) {
        final cat = v['medicalCategory']?.toString().toUpperCase();
        return cat == 'DOCTOR' || cat == 'PHYSICIAN';
      }).toList();
    }
    if (_selectedStopFilter == 'CHEMIST') {
      return _visits.where((v) {
        final cat = v['medicalCategory']?.toString().toUpperCase();
        return cat == 'CHEMIST' || cat == 'RETAILER' || cat == 'PHARMACY';
      }).toList();
    }
    if (_selectedStopFilter == 'PENDING') {
      return _visits
          .where((v) => v['status'] == 'PLANNED' || v['status'] == 'IN_PROGRESS')
          .toList();
    }
    if (_selectedStopFilter == 'COMPLETED') {
      return _visits.where((v) => v['status'] == 'COMPLETED').toList();
    }
    return _visits;
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

  Future<void> _startNewAssignedRoute(Map<String, dynamic> assignment) async {
    final routeId = assignment['routeId']?.toString();
    final session = ref.read(authControllerProvider).session;
    final userId = session?.userId;
    if (routeId == null || userId == null) return;

    setState(() => _loading = true);
    final api = ref.read(apiClientProvider);
    try {
      final todayStr = DateTime.now().toIso8601String().split('T')[0];
      final exec = await api.startExecution(
        routeId: routeId,
        salespersonId: userId,
        executionDate: todayStr,
      );
      final execId = exec['id']?.toString();
      if (execId != null) {
        try {
          await api.startRoute(execId);
        } catch (_) {}
      }
      _showSuccess('Today\'s field run started!');
      await _loadData();
    } catch (e) {
      _showError('Failed to start beat run: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _checkIn(String visitId) async {
    if (_inFlightCheckIns.contains(visitId)) return;
    setState(() => _inFlightCheckIns.add(visitId));

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
      final errStr = e.toString().toLowerCase();
      // If already in progress or completed, refresh state smoothly without error snackbar
      if (errStr.contains('already in progress') ||
          errStr.contains('status code of 400') ||
          errStr.contains('invalid_state')) {
        await _loadData();
      } else if (_isNetworkError(e)) {
        await _enqueueAction(
          'CHECK_IN',
          '/api/v1/field-sales/visits/$visitId/check-in',
          {'latitude': latitude, 'longitude': longitude},
        );
      } else {
        _showError('Check-in failed: $e');
      }
    } finally {
      if (mounted) setState(() => _inFlightCheckIns.remove(visitId));
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
            medicalCategory: visit['medicalCategory']?.toString(),
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
    String paymentMethod = 'CASH';
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record Collection'),
        content: StatefulBuilder(
          builder: (ctx, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Amount *',
                  hintText: 'e.g. 2500',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: paymentMethod,
                decoration: const InputDecoration(labelText: 'Payment method'),
                items: const [
                  DropdownMenuItem(value: 'CASH', child: Text('Cash')),
                  DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                  DropdownMenuItem(value: 'CARD', child: Text('Card')),
                  DropdownMenuItem(value: 'BANK_TRANSFER', child: Text('Bank transfer')),
                  DropdownMenuItem(value: 'CHEQUE', child: Text('Cheque')),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => paymentMethod = value);
                },
              ),
            ],
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
          .recordCollection(visitId, collectionAmount: collectionAmount, paymentMethod: paymentMethod);
      _showSuccess('Collection recorded');
      await _loadData();
    } catch (e) {
      if (_isNetworkError(e)) {
        await _enqueueAction(
          'RECORD_COLLECTION',
          '/api/v1/field-sales/visits/$visitId/record-collection',
          {'collectionAmount': collectionAmount, 'paymentMethod': paymentMethod},
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
      final pod = await ref.read(apiClientProvider).recordPod(body);
      _showSuccess('Proof of delivery recorded');
      final podId = pod['id']?.toString();
      if (podId != null && podId.isNotEmpty) {
        await _maybeAttachPodPhoto(podId);
      }
    } catch (e) {
      if (_isNetworkError(e)) {
        // Offline: queue the JSON record. Photo attach is skipped — we
        // don't have a POD id yet, so the salesperson can attach via the
        // ERP screen once the queued record syncs through.
        await _enqueueAction('RECORD_POD', '/api/v1/proof-of-delivery', body);
      } else {
        _showError('Failed to record POD: $e');
      }
    }
  }

  /// After a POD posts successfully, offers the salesperson a chance to
  /// capture proof — either a photo (signed paper slip or goods at the
  /// door) or an on-screen finger signature. Uploaded through the shared
  /// AttachmentService. The salesperson can attach more later from the
  /// ERP screen — this is the at-the-door fast path.
  Future<void> _maybeAttachPodPhoto(String podId) async {
    if (!mounted) return;
    final choice = await showModalBottomSheet<_PodAttachChoice>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              subtitle: const Text('Signed slip or goods at the door'),
              onTap: () => Navigator.pop(ctx, _PodAttachChoice.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Pick from gallery'),
              onTap: () => Navigator.pop(ctx, _PodAttachChoice.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.draw_outlined),
              title: const Text('Sign on screen'),
              subtitle: const Text('Recipient signs with their finger'),
              onTap: () => Navigator.pop(ctx, _PodAttachChoice.signature),
            ),
            ListTile(
              leading: const Icon(Icons.skip_next_outlined),
              title: const Text('Skip'),
              onTap: () => Navigator.pop(ctx, null),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case _PodAttachChoice.camera:
        await _pickAndUploadImage(podId, ImageSource.camera);
      case _PodAttachChoice.gallery:
        await _pickAndUploadImage(podId, ImageSource.gallery);
      case _PodAttachChoice.signature:
        await _captureSignatureForPod(podId);
    }
  }

  Future<void> _pickAndUploadImage(String podId, ImageSource source) async {
    try {
      // Cap dimensions so a 12 MP phone shot doesn't blow up the upload —
      // signed-slip / door photos are still readable at 1600px wide and
      // ~70% JPEG quality.
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 70,
      );
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      await ref.read(apiClientProvider).attachPodFile(
            podId,
            bytes: bytes,
            filename: picked.name,
          );
      _showSuccess('Photo attached');
    } catch (e) {
      _showError('Photo upload failed: $e');
    }
  }

  /// Opens a fullscreen signature pad. On save, the drawn signature is
  /// exported to PNG bytes and uploaded against the POD via the same
  /// attachment endpoint as photos.
  Future<void> _captureSignatureForPod(String podId) async {
    final bytes = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const _SignaturePadScreen(),
      ),
    );
    if (bytes == null || bytes.isEmpty || !mounted) return;
    try {
      await ref.read(apiClientProvider).attachPodFile(
            podId,
            bytes: bytes,
            filename: 'signature.png',
          );
      _showSuccess('Signature attached');
    } catch (e) {
      _showError('Signature upload failed: $e');
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

  Future<void> _openRcpa(Map<String, dynamic> visit) async {
    final visitId = visit['id']?.toString() ?? '';
    final contactId = visit['contactId']?.toString() ?? '';
    final contactName = visit['contactName']?.toString() ?? 'Chemist';

    final recorded = await RcpaSheet.show(
      context,
      chemistId: contactId,
      chemistName: contactName,
      fieldVisitId: visitId,
    );
    if (recorded == true && mounted) {
      await _loadData();
    }
  }

  Future<void> _recordJointVisit(String visitId) async {
    final managerCtl = TextEditingController();
    String designation = 'ASM';
    final notesCtl = TextEditingController();

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.groups_outlined, color: Color(0xFF2563EB)),
              SizedBox(width: 8),
              Text('Record Joint Visit'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: managerCtl,
                decoration: const InputDecoration(
                  labelText: 'Manager Name *',
                  hintText: 'e.g. Ramesh Sharma',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: designation,
                decoration: const InputDecoration(labelText: 'Designation'),
                items: const [
                  DropdownMenuItem(value: 'ASM', child: Text('Area Sales Manager (ASM)')),
                  DropdownMenuItem(value: 'RSM', child: Text('Regional Sales Manager (RSM)')),
                  DropdownMenuItem(value: 'ZSM', child: Text('Zonal Sales Manager (ZSM)')),
                  DropdownMenuItem(value: 'PMT', child: Text('Product Management Team (PMT)')),
                ],
                onChanged: (val) {
                  if (val != null) setDialogState(() => designation = val);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtl,
                decoration: const InputDecoration(
                  labelText: 'Joint Visit Notes',
                  hintText: 'Doctor reaction, detailing feedback...',
                ),
                maxLines: 2,
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
                if (managerCtl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Please enter manager name')),
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Save Joint Visit'),
            ),
          ],
        ),
      ),
    );

    if (proceed != true || !mounted) return;

    try {
      await ref.read(apiClientProvider).markJointVisit(
            visitId,
            jointWith: managerCtl.text.trim(),
            managerDesignation: designation,
            notes: notesCtl.text.trim(),
          );
      _showSuccess('Joint visit recorded with $designation ${managerCtl.text.trim()}');
      await _loadData();
    } catch (e) {
      _showError('Failed to record joint visit: $e');
    }
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
        title: 'My Route',
        subtitle: 'Demo mode — login to see real visits.',
        children: [],
      );
    }

    final execStatus = _activeExecution?['status']?.toString() ?? 'NONE';

    return RefreshIndicator(
      onRefresh: _loadData,
      child: PageScaffold(
        title: 'My Daily Route',
        subtitle: 'Geo-verified customer stops, chemist POBs & detailing cockpit.',
        children: [
          _buildAttendanceBar(theme),
          const SizedBox(height: 12),
          if (_error != null) ...[
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_activeExecution != null)
            _buildRoutePulseCard(theme, execStatus)
          else if (_assignments.isNotEmpty)
            _buildStartRouteBanner(theme)
          else
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(Icons.event_busy_rounded, size: 40, color: Colors.grey.shade400),
                    const SizedBox(height: 10),
                    Text(
                      'No Active Route for Today',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'No route run was scheduled or started for today. Check your monthly Tour Plan or pull down to refresh.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 14),
          if (_visits.isNotEmpty) ...[
            _buildFilterChips(theme),
            const SizedBox(height: 12),
          ],
          if (_filteredVisits.isEmpty && _activeExecution != null)
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    _visits.isEmpty
                        ? 'No stops mapped to this route.'
                        : 'No stops matching "$_selectedStopFilter" filter.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
              ),
            )
          else
            ..._filteredVisits.map((visit) => _buildVisitCard(visit, theme)),
        ],
      ),
    );
  }

  Widget _buildAttendanceBar(ThemeData theme) {
    final att = _attendance;
    final punchedIn = att?['punchedIn'] == true;
    final punchedOut = att?['punchedOut'] == true;
    final inTime = _punchTime(att?['punchInTime']?.toString());
    final outTime = _punchTime(att?['punchOutTime']?.toString());

    Color bg;
    Color border;
    Widget statusDot;
    String statusText;
    Widget actionBtn;

    if (punchedIn && !punchedOut) {
      bg = const Color(0xFFF0FDF4);
      border = const Color(0xFFBBF7D0);
      statusDot = Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Color(0xFF16A34A),
          shape: BoxShape.circle,
        ),
      );
      statusText = 'ON DUTY · Punch In: $inTime';
      actionBtn = OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          foregroundColor: const Color(0xFFDC2626),
          side: const BorderSide(color: Color(0xFFFCA5A5)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        ),
        onPressed: () => _punch(isIn: false),
        icon: const Icon(Icons.logout, size: 14),
        label: const Text('End Shift', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      );
    } else if (punchedOut) {
      bg = const Color(0xFFF8FAFC);
      border = const Color(0xFFE2E8F0);
      statusDot = Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: Colors.grey.shade400,
          shape: BoxShape.circle,
        ),
      );
      statusText = 'SHIFT CLOSED · In: $inTime | Out: $outTime';
      actionBtn = const Chip(
        label: Text('Shift Completed', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
        backgroundColor: Color(0xFFF1F5F9),
        visualDensity: VisualDensity.compact,
      );
    } else {
      bg = const Color(0xFFFFFBEB);
      border = const Color(0xFFFDE68A);
      statusDot = Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Color(0xFFD97706),
          shape: BoxShape.circle,
        ),
      );
      statusText = 'NOT PUNCHED IN · Mark duty attendance';
      actionBtn = FilledButton.icon(
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          backgroundColor: const Color(0xFF0B6B5E),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
        onPressed: () => _punch(isIn: true),
        icon: const Icon(Icons.fingerprint, size: 16),
        label: const Text('Punch In', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          statusDot,
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              statusText,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          actionBtn,
        ],
      ),
    );
  }

  Widget _buildRoutePulseCard(ThemeData theme, String execStatus) {
    final routeName = _activeExecution!['routeName']?.toString() ?? 'Daily Beat Run';
    final completedStops = _visits.where((v) => v['status'] == 'COMPLETED').length;
    final totalStops = _visits.length;
    final percent = totalStops > 0 ? (completedStops / totalStops) : 0.0;

    double totalOrders = 0.0;
    double totalCollections = 0.0;
    for (final v in _visits) {
      totalOrders += (v['orderValue'] as num?)?.toDouble() ?? 0.0;
      totalCollections += (v['collectionAmount'] as num?)?.toDouble() ?? 0.0;
    }

    Color statusColor = const Color(0xFF0B6B5E);
    String statusLabel = 'IN PROGRESS';
    if (execStatus == 'PLANNED') {
      statusColor = const Color(0xFFD97706);
      statusLabel = 'PLANNED';
    } else if (execStatus == 'COMPLETED') {
      statusColor = const Color(0xFF2563EB);
      statusLabel = 'COMPLETED';
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        routeName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$completedStops of $totalStops stops completed · ${(percent * 100).toInt()}% progress',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percent,
                minHeight: 6,
                backgroundColor: const Color(0xFFE2E8F0),
                valueColor: AlwaysStoppedAnimation<Color>(
                  percent >= 1.0 ? const Color(0xFF10B981) : const Color(0xFF0B6B5E),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF1F5F9)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('POB Orders', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                        const SizedBox(height: 2),
                        Text(
                          '₹${totalOrders.toStringAsFixed(0)}',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF0B6B5E)),
                        ),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 28, color: const Color(0xFFE2E8F0)),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Collections', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                          const SizedBox(height: 2),
                          Text(
                            '₹${totalCollections.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF2563EB)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(width: 1, height: 28, color: const Color(0xFFE2E8F0)),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Coverage', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                          const SizedBox(height: 2),
                          Text(
                            '$completedStops/$totalStops',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (execStatus == 'PLANNED') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0B6B5E),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Start Route Run', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: _startRoute,
                ),
              ),
            ] else if (execStatus == 'IN_PROGRESS') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0B6B5E),
                    side: const BorderSide(color: Color(0xFF0B6B5E)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Complete Today\'s Beat Run', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: _completeRoute,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStartRouteBanner(ThemeData theme) {
    final assignment = _assignments.first;
    final routeName = assignment['routeName']?.toString() ?? 'Assigned Daily Beat';
    final dayOfWeek = assignment['dayOfWeek']?.toString() ?? 'Today';
    final frequency = assignment['frequency']?.toString() ?? 'WEEKLY';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFA7F3D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.alt_route_rounded, color: Color(0xFF047857), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      routeName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF065F46),
                      ),
                    ),
                    Text(
                      'Beat Schedule: $dayOfWeek · $frequency',
                      style: const TextStyle(color: Color(0xFF047857), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Ready to start today\'s field beat? Tap below to initialize customer stops, doctor visual aids, and chemist POB booking.',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0B6B5E),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: const Text('Start Today\'s Beat Run', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => _startNewAssignedRoute(assignment),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(ThemeData theme) {
    final docCount = _visits.where((v) {
      final c = v['medicalCategory']?.toString().toUpperCase();
      return c == 'DOCTOR' || c == 'PHYSICIAN';
    }).length;
    final chmCount = _visits.where((v) {
      final c = v['medicalCategory']?.toString().toUpperCase();
      return c == 'CHEMIST' || c == 'RETAILER' || c == 'PHARMACY';
    }).length;
    final pendingCount = _visits.where((v) => v['status'] == 'PLANNED' || v['status'] == 'IN_PROGRESS').length;
    final doneCount = _visits.where((v) => v['status'] == 'COMPLETED').length;

    Widget chip(String key, String label, int count) {
      final isSel = _selectedStopFilter == key;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => _selectedStopFilter = key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isSel ? const Color(0xFF0B6B5E) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSel ? const Color(0xFF0B6B5E) : const Color(0xFFE2E8F0),
              ),
            ),
            child: Text(
              '$label ($count)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSel ? FontWeight.w700 : FontWeight.w600,
                color: isSel ? Colors.white : const Color(0xFF475569),
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('ALL', 'All Stops', _visits.length),
          chip('DOCTOR', 'Doctors', docCount),
          chip('CHEMIST', 'Chemists', chmCount),
          chip('PENDING', 'Pending', pendingCount),
          chip('COMPLETED', 'Completed', doneCount),
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
    final category = visit['medicalCategory']?.toString().toUpperCase() ?? '';
    final isDoctor = category == 'DOCTOR' || category == 'PHYSICIAN';
    final city = visit['city']?.toString() ?? '';
    final address = visit['address']?.toString() ?? '';
    final phone = visit['contactPhone']?.toString() ?? '';
    final outstandingAr = (visit['outstandingAr'] as num?)?.toDouble() ?? 0.0;

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'IN_PROGRESS':
        statusColor = const Color(0xFFD97706);
        statusLabel = 'In Visit';
      case 'COMPLETED':
        statusColor = const Color(0xFF16A34A);
        statusLabel = 'Done';
      case 'SKIPPED':
        statusColor = const Color(0xFFDC2626);
        statusLabel = 'Skipped';
      default:
        statusColor = const Color(0xFF2563EB);
        statusLabel = 'Planned';
    }

    final avatarBg = isDoctor ? const Color(0xFFF3E8FF) : const Color(0xFFCCFBF1);
    final avatarColor = isDoctor ? const Color(0xFF7E22CE) : const Color(0xFF0F766E);
    final avatarIcon = isDoctor ? Icons.medical_services_outlined : Icons.storefront_outlined;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: status == 'IN_PROGRESS'
              ? const Color(0xFF0B6B5E)
              : const Color(0xFFE2E8F0),
          width: status == 'IN_PROGRESS' ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: avatarBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(avatarIcon, color: avatarColor, size: 22),
                    ),
                    if (seq != null)
                      Positioned(
                        top: -4,
                        left: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$seq',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contactName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (category.isNotEmpty) category,
                          if (city.isNotEmpty) city,
                        ].join(' · '),
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),

            if (phone.isNotEmpty || address.isNotEmpty || outstandingAr > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                ),
                child: Row(
                  children: [
                    if (phone.isNotEmpty) ...[
                      InkWell(
                        onTap: () => _callContact(phone),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0F2FE),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.phone, size: 13, color: Color(0xFF0369A1)),
                              SizedBox(width: 4),
                              Text('Call', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0369A1))),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => _whatsappContact(phone, contactName),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.chat_bubble_outline, size: 13, color: Color(0xFF15803D)),
                              SizedBox(width: 4),
                              Text('WhatsApp', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF15803D))),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    InkWell(
                      onTap: () => _openMapDirections(contactName, address, city),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.directions, size: 13, color: Color(0xFF475569)),
                            SizedBox(width: 4),
                            Text('Maps', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (!isDoctor && outstandingAr > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Udhar: ₹${outstandingAr.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFB91C1C),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],

            if (visit['jointVisitUserId'] != null || visit['jointWith'] != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFC7D2FE)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.groups, size: 14, color: Color(0xFF4F46E5)),
                    const SizedBox(width: 6),
                    Text(
                      visit['jointWith'] != null
                          ? 'Joint Visit: ${visit['jointWith']} (${visit['managerDesignation'] ?? 'ASM'})'
                          : 'Joint Visit (${visit['managerDesignation'] ?? 'ASM'})',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF4F46E5),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (checkInTime != null || (orderValue != null && orderValue > 0) || (collectionAmount != null && collectionAmount > 0)) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (checkInTime != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.access_time, size: 12, color: Color(0xFF64748B)),
                          const SizedBox(width: 4),
                          Text(
                            checkOutTime != null
                                ? 'In: ${_punchTime(checkInTime)} · Out: ${_punchTime(checkOutTime)}'
                                : 'In: ${_punchTime(checkInTime)}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
                          ),
                        ],
                      ),
                    ),
                  if (orderValue != null && orderValue > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.shopping_bag_outlined, size: 12, color: Color(0xFF059669)),
                          const SizedBox(width: 4),
                          Text('Order: ₹${orderValue.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF059669))),
                        ],
                      ),
                    ),
                  if (collectionAmount != null && collectionAmount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.payments_outlined, size: 12, color: Color(0xFF2563EB)),
                          const SizedBox(width: 4),
                          Text('Collected: ₹${collectionAmount.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                        ],
                      ),
                    ),
                ],
              ),
            ],

            if (status == 'SKIPPED' && skipReason != null) ...[
              const SizedBox(height: 6),
              Text(
                'Skipped Reason: $skipReason',
                style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ],

            const SizedBox(height: 12),
            if (status == 'PLANNED') ...[
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0B6B5E),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _inFlightCheckIns.contains(visitId)
                          ? null
                          : () => _checkIn(visitId),
                      icon: _inFlightCheckIns.contains(visitId)
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.location_on, size: 16),
                      label: Text(
                        _inFlightCheckIns.contains(visitId) ? 'Checking in…' : 'Check In at Location',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      side: BorderSide(color: Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _skipVisit(visitId),
                    child: const Text('Skip'),
                  ),
                ],
              ),
            ],

            if (status == 'IN_PROGRESS') ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0B6B5E),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _checkOut(visitId),
                  icon: const Icon(Icons.check_circle, size: 18),
                  label: const Text('Check Out & Finish Call', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (isDoctor) ...[
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFF3E8FF),
                        foregroundColor: const Color(0xFF7E22CE),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _logDetailing(visitId),
                      icon: const Icon(Icons.medication, size: 16),
                      label: const Text('Detailing & Samples', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _showAids(visitId),
                      icon: const Icon(Icons.auto_stories, size: 16),
                      label: const Text('Visual Aids'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _openRcpa(visit),
                      icon: const Icon(Icons.analytics_outlined, size: 16),
                      label: const Text('RCPA Audit'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _recordJointVisit(visitId),
                      icon: const Icon(Icons.groups_outlined, size: 16),
                      label: const Text('Joint Call'),
                    ),
                  ] else ...[
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFCCFBF1),
                        foregroundColor: const Color(0xFF0F766E),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _showOrderOptions(visit),
                      icon: const Icon(Icons.shopping_bag, size: 16),
                      label: const Text('Book POB Order', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFEFF6FF),
                        foregroundColor: const Color(0xFF1D4ED8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _recordCollection(visitId),
                      icon: const Icon(Icons.payments, size: 16),
                      label: const Text('Collect Cash/UPI', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _openRcpa(visit),
                      icon: const Icon(Icons.analytics_outlined, size: 16),
                      label: const Text('RCPA'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _recordPod(visit),
                      icon: const Icon(Icons.assignment_turned_in, size: 16),
                      label: const Text('POD'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _recordJointVisit(visitId),
                      icon: const Icon(Icons.groups_outlined, size: 16),
                      label: const Text('Joint'),
                    ),
                  ],
                ],
              ),
            ],

            if (status == 'COMPLETED') ...[
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (!isDoctor) ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _showOrderOptions(visit),
                      icon: const Icon(Icons.shopping_bag_outlined, size: 15),
                      label: const Text('Order / POB', style: TextStyle(fontSize: 12)),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _recordCollection(visitId),
                      icon: const Icon(Icons.payments_outlined, size: 15),
                      label: const Text('Collect', style: TextStyle(fontSize: 12)),
                    ),
                  ] else ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _logDetailing(visitId),
                      icon: const Icon(Icons.medication_outlined, size: 15),
                      label: const Text('Detailing', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _openRcpa(visit),
                    icon: const Icon(Icons.analytics_outlined, size: 15),
                    label: const Text('RCPA', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
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
  List<Map<String, dynamic>> _catalogItems = [];
  bool _loadingCatalog = false;

  static const _quickMedicines = [
    '24 Orthomoon Capsule',
    'Mustmoon Gold Capsule',
    'Moonliv Syrup',
    'Moon Mansosave Syrup',
    'Platoford Tablet',
    'Craston Capsule',
  ];

  static const _quickGifts = [
    'Visual Aid',
    'Note Pad & Pen',
    'Sample Kit',
    'Prescription Pad',
  ];

  @override
  void initState() {
    super.initState();
    _rows = List.of(widget.initialRows);
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    setState(() => _loadingCatalog = true);
    try {
      final raw = await ref.read(apiClientProvider).searchItems('');
      if (mounted) {
        setState(() {
          _catalogItems = raw.whereType<Map<String, dynamic>>().toList();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingCatalog = false);
    }
  }

  @override
  void dispose() {
    _productCtl.dispose();
    _samplesCtl.dispose();
    _giftCtl.dispose();
    super.dispose();
  }

  void _selectProduct(String name) {
    setState(() {
      _productCtl.text = name;
      if (_samplesCtl.text == '0') {
        _samplesCtl.text = '1';
      }
    });
  }

  void _stepSamples(int delta) {
    final current = int.tryParse(_samplesCtl.text) ?? 0;
    final next = (current + delta).clamp(0, 999);
    setState(() {
      _samplesCtl.text = next.toString();
    });
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Detailing & samples recorded successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
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
    final theme = Theme.of(context);
    final displayedSuggestions = _catalogItems.isNotEmpty
        ? _catalogItems.take(8).map((it) => it['name']?.toString() ?? '').where((n) => n.isNotEmpty).toList()
        : _quickMedicines;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Products & Promo',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Record detailed brands, physician samples, and gifts.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  if (_loadingCatalog)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 10),

              // Detailed items list
              if (_rows.isNotEmpty) ...[
                Text(
                  'Detailed Products (${_rows.length})',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                ..._rows.asMap().entries.map((entry) {
                  final item = entry.value;
                  final sampleCount = item['sampleQty'] ?? 0;
                  final gift = item['giftName'] as String?;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.medication, color: theme.colorScheme.primary, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['productName']?.toString() ?? '',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 2,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.blue.shade200),
                                      ),
                                      child: Text(
                                        '$sampleCount samples',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.blue.shade800,
                                        ),
                                      ),
                                    ),
                                    if (gift != null && gift.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.purple.shade50,
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.purple.shade200),
                                        ),
                                        child: Text(
                                          'Gift: $gift',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.purple.shade800,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                            onPressed: () => setState(() => _rows.removeAt(entry.key)),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const Divider(height: 16),
              ],

              // Product input + suggestions
              Text(
                'Add Product & Detailing',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Autocomplete<String>(
                initialValue: TextEditingValue(text: _productCtl.text),
                optionsBuilder: (textEditingValue) {
                  if (textEditingValue.text.isEmpty) {
                    return displayedSuggestions;
                  }
                  final query = textEditingValue.text.toLowerCase();
                  if (_catalogItems.isNotEmpty) {
                    return _catalogItems
                        .map((it) => it['name']?.toString() ?? '')
                        .where((name) => name.toLowerCase().contains(query));
                  }
                  return _quickMedicines.where((m) => m.toLowerCase().contains(query));
                },
                onSelected: (selection) => _selectProduct(selection),
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  // Synchronize
                  controller.addListener(() {
                    if (_productCtl.text != controller.text) {
                      _productCtl.text = controller.text;
                    }
                  });
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      labelText: 'Medicine / Brand detailed *',
                      hintText: 'Search or tap quick brand below',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: controller.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                controller.clear();
                                _productCtl.clear();
                              },
                            )
                          : null,
                    ),
                  );
                },
              ),
              const SizedBox(height: 6),

              // Quick brand chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: displayedSuggestions.map((brand) {
                    final isSelected = _productCtl.text == brand;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        avatar: Icon(
                          Icons.medication,
                          size: 14,
                          color: isSelected ? Colors.teal.shade800 : Colors.grey.shade700,
                        ),
                        label: Text(
                          brand,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected ? Colors.teal.shade900 : null,
                          ),
                        ),
                        backgroundColor: isSelected ? Colors.teal.shade50 : null,
                        side: isSelected ? BorderSide(color: Colors.teal.shade400) : null,
                        onPressed: () => _selectProduct(brand),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),

              // Samples Stepper
              Row(
                children: [
                  const Text('Samples Given:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    icon: const Icon(Icons.remove, size: 16),
                    onPressed: () => _stepSamples(-1),
                    visualDensity: VisualDensity.compact,
                  ),
                  SizedBox(
                    width: 48,
                    child: TextField(
                      controller: _samplesCtl,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  IconButton.outlined(
                    icon: const Icon(Icons.add, size: 16),
                    onPressed: () => _stepSamples(1),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 8),
                  ...[0, 1, 2, 5].map((q) => Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: ChoiceChip(
                          label: Text('$q'),
                          selected: _samplesCtl.text == '$q',
                          onSelected: (_) => setState(() => _samplesCtl.text = '$q'),
                          visualDensity: VisualDensity.compact,
                        ),
                      )),
                ],
              ),
              const SizedBox(height: 12),

              // Gift input + Quick gifts
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _giftCtl,
                      decoration: const InputDecoration(
                        labelText: 'Promotional Gift / Input (optional)',
                        hintText: 'e.g. Visual Aid, Note Pad',
                        prefixIcon: Icon(Icons.card_giftcard, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: _addRow,
                    icon: const Icon(Icons.add),
                    tooltip: 'Add to detailing list',
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _quickGifts.map((gift) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          avatar: const Icon(Icons.card_giftcard, size: 14),
                          label: Text(gift, style: const TextStyle(fontSize: 12)),
                          onPressed: () => setState(() => _giftCtl.text = gift),
                        ),
                      )).toList(),
                ),
              ),
              const SizedBox(height: 16),

              // Save button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save),
                  label: Text(_saving ? 'Saving Detailing…' : 'Save Detailing & Samples'),
                ),
              ),
            ],
          ),
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
                "GPS and timestamp will be stamped automatically. After "
                "saving, you can snap a photo of the signed slip or "
                "delivery snapshot to attach.",
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

/// What the salesperson picked in the post-record attach sheet.
enum _PodAttachChoice { camera, gallery, signature }

/// Fullscreen on-screen signature pad. The recipient signs with a finger,
/// the salesperson taps Save, and the drawn strokes are exported to PNG
/// bytes returned via Navigator.pop. Cancel returns null.
class _SignaturePadScreen extends StatefulWidget {
  const _SignaturePadScreen();

  @override
  State<_SignaturePadScreen> createState() => _SignaturePadScreenState();
}

class _SignaturePadScreenState extends State<_SignaturePadScreen> {
  late final SignatureController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_controller.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign before saving')),
      );
      return;
    }
    final bytes = await _controller.toPngBytes();
    if (!mounted) return;
    Navigator.of(context).pop(bytes?.toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recipient signature'),
        actions: [
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.clear(),
          ),
        ],
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Hand the phone to the recipient. Sign inside the box.',
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Signature(
                  controller: _controller,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save),
                      label: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
