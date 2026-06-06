import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/location/location_service.dart';
import '../auth/auth_controller.dart';
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
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
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
    try {
      final loc = await _locationService.currentLocation();
      await ref
          .read(apiClientProvider)
          .checkIn(
            visitId,
            latitude: loc?.latitude ?? 0,
            longitude: loc?.longitude ?? 0,
          );
      if (loc == null) _showInfo('Location unavailable — using default');
      _showSuccess('Checked in');
      await _loadData();
    } catch (e) {
      _showError('Check-in failed: $e');
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

    try {
      final loc = await _locationService.currentLocation();
      final notes = notesCtl.text.trim();
      await ref
          .read(apiClientProvider)
          .checkOut(
            visitId,
            latitude: loc?.latitude ?? 0,
            longitude: loc?.longitude ?? 0,
            notes: notes.isNotEmpty ? notes : null,
          );
      _showSuccess('Checked out');
      await _loadData();
    } catch (e) {
      _showError('Check-out failed: $e');
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

    try {
      await ref
          .read(apiClientProvider)
          .recordOrder(
            visitId,
            salesOrderId: soIdCtl.text.trim(),
            orderValue: double.tryParse(valueCtl.text.trim()) ?? 0,
          );
      _showSuccess('Order recorded');
      await _loadData();
    } catch (e) {
      _showError('Failed to record order: $e');
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

    try {
      await ref
          .read(apiClientProvider)
          .recordCollection(
            visitId,
            collectionAmount: double.tryParse(amountCtl.text.trim()) ?? 0,
          );
      _showSuccess('Collection recorded');
      await _loadData();
    } catch (e) {
      _showError('Failed to record collection: $e');
    }
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
                    onPressed: () => _recordOrder(visitId),
                    icon: const Icon(Icons.shopping_cart, size: 18),
                    label: const Text('Order'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _recordCollection(visitId),
                    icon: const Icon(Icons.payments, size: 18),
                    label: const Text('Collect'),
                  ),
                ],
                if (status == 'COMPLETED') ...[
                  OutlinedButton.icon(
                    onPressed: () => _recordOrder(visitId),
                    icon: const Icon(Icons.shopping_cart, size: 18),
                    label: const Text('Order'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _recordCollection(visitId),
                    icon: const Icon(Icons.payments, size: 18),
                    label: const Text('Collect'),
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
