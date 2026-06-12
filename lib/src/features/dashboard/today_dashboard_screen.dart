import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/location/location_service.dart';
import '../auth/auth_controller.dart';
import '../shared/field_widgets.dart';

class TodayDashboardScreen extends ConsumerStatefulWidget {
  const TodayDashboardScreen({super.key});

  @override
  ConsumerState<TodayDashboardScreen> createState() =>
      _TodayDashboardScreenState();
}

class _TodayDashboardScreenState extends ConsumerState<TodayDashboardScreen> {
  bool _loading = true;
  Map<String, dynamic> _dashboard = {};
  List<dynamic> _todayExecutions = [];
  List<dynamic> _targets = [];
  Map<String, dynamic>? _attendance;
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
      final now = DateTime.now();
      final from = DateTime(
        now.year,
        now.month,
        1,
      ).toIso8601String().split('T')[0];
      final to = now.toIso8601String().split('T')[0];

      final results = await Future.wait([
        api.getDashboard(from: from, to: to),
        api.getMyTodayExecutions(),
        api.getMyTargets(),
      ]);
      Map<String, dynamic>? attendance;
      try {
        attendance = await api.getAttendanceToday();
      } catch (_) {
        // attendance is optional — never block the dashboard
      }
      _attendance = attendance;

      if (mounted) {
        setState(() {
          _dashboard = results[0] as Map<String, dynamic>;
          _todayExecutions = results[1] as List<dynamic>;
          _targets = results[2] as List<dynamic>;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _punch({required bool isIn}) async {
    FieldLocation? loc;
    try {
      loc = await _locationService.currentLocation();
    } catch (_) {
      loc = null;
    }
    try {
      final api = ref.read(apiClientProvider);
      if (isIn) {
        await api.punchIn(latitude: loc?.latitude, longitude: loc?.longitude);
      } else {
        await api.punchOut(latitude: loc?.latitude, longitude: loc?.longitude);
      }
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Punch failed: $e')));
      }
    }
  }

  Future<void> _applyLeave() async {
    DateTimeRange? range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (range == null || !mounted) return;

    String type = 'CASUAL';
    final reasonCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Apply Leave'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: 'CASUAL', child: Text('Casual')),
                  DropdownMenuItem(value: 'SICK', child: Text('Sick')),
                  DropdownMenuItem(value: 'EARNED', child: Text('Earned')),
                  DropdownMenuItem(value: 'UNPAID', child: Text('Unpaid')),
                ],
                onChanged: (v) => setDialogState(() => type = v ?? 'CASUAL'),
              ),
              TextField(
                controller: reasonCtl,
                decoration: const InputDecoration(labelText: 'Reason'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Apply')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    try {
      await ref.read(apiClientProvider).applyLeave(
            fromDate: range.start.toIso8601String().split('T')[0],
            toDate: range.end.toIso8601String().split('T')[0],
            leaveType: type,
            reason: reasonCtl.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Leave requested — pending approval')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Leave request failed: $e')));
      }
    }
  }

  String _punchTime(String? iso) {
    final t = iso != null ? DateTime.tryParse(iso)?.toLocal() : null;
    if (t == null) return '--:--';
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Widget _attendanceCard() {
    final punchedIn = _attendance?['punchInAt'] != null;
    final punchedOut = _attendance?['punchOutAt'] != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              punchedOut
                  ? Icons.task_alt
                  : punchedIn
                      ? Icons.timer_outlined
                      : Icons.badge_outlined,
              color: punchedIn && !punchedOut ? Colors.green : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                punchedOut
                    ? 'Day done · in ${_punchTime(_attendance?['punchInAt']?.toString())}'
                        ' / out ${_punchTime(_attendance?['punchOutAt']?.toString())}'
                    : punchedIn
                        ? 'On duty since ${_punchTime(_attendance?['punchInAt']?.toString())}'
                        : 'Not punched in yet',
              ),
            ),
            if (!punchedIn)
              FilledButton(
                onPressed: () => _punch(isIn: true),
                child: const Text('Punch In'),
              )
            else if (!punchedOut)
              OutlinedButton(
                onPressed: () => _punch(isIn: false),
                child: const Text('Punch Out'),
              ),
            IconButton(
              tooltip: 'Apply leave',
              icon: const Icon(Icons.beach_access_outlined),
              onPressed: _applyLeave,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).session;
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (session?.isDemo == true) {
      return PageScaffold(
        title: 'Today',
        subtitle: 'Demo mode — login with real credentials to see live data.',
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Demo mode shows sample data. Login with your Katasticho ERP credentials to connect to the real backend.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final totalRoutes = (_dashboard['totalRoutes'] as num?)?.toInt() ?? 0;
    final totalVisits = (_dashboard['totalVisits'] as num?)?.toInt() ?? 0;
    final productivePercent =
        (_dashboard['productivePercent'] as num?)?.toDouble() ?? 0;
    final totalOrders =
        (_dashboard['totalOrders'] as num?)?.toDouble() ??
        (_dashboard['totalOrdersValue'] as num?)?.toDouble() ??
        0;
    final totalCollections =
        (_dashboard['totalCollections'] as num?)?.toDouble() ?? 0;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: PageScaffold(
        title: 'Today',
        subtitle: '${session?.orgName ?? 'Organisation'} field workspace.',
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

          _attendanceCard(),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: MetricTile(
                  icon: Icons.route,
                  label: 'Routes (MTD)',
                  value: '$totalRoutes',
                  tint: const Color(0xFF2563EB),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricTile(
                  icon: Icons.storefront,
                  label: 'Visits (MTD)',
                  value: '$totalVisits',
                  tint: const Color(0xFF059669),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  icon: Icons.trending_up,
                  label: 'Productive %',
                  value: '${productivePercent.toStringAsFixed(1)}%',
                  tint: const Color(0xFFF59E0B),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricTile(
                  icon: Icons.payments,
                  label: 'Collections',
                  value: _formatCurrency(totalCollections),
                  tint: const Color(0xFF7C3AED),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          MetricTile(
            icon: Icons.shopping_cart,
            label: 'Orders (MTD)',
            value: _formatCurrency(totalOrders),
            tint: const Color(0xFF0891B2),
          ),
          const SizedBox(height: 20),

          Text(
            "Today's Routes",
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          if (_todayExecutions.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.event_busy, color: Colors.grey.shade400),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('No routes assigned for today.'),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._todayExecutions.map((exec) {
              final routeName =
                  exec['routeName']?.toString() ??
                  exec['routeId']?.toString() ??
                  'Route';
              final status = exec['status']?.toString() ?? 'PLANNED';
              final tv = (exec['totalVisits'] as num?)?.toInt() ?? 0;
              final cv = (exec['completedVisits'] as num?)?.toInt() ?? 0;

              Color statusColor;
              switch (status) {
                case 'IN_PROGRESS':
                  statusColor = Colors.orange;
                case 'COMPLETED':
                  statusColor = Colors.green;
                default:
                  statusColor = Colors.blue;
              }

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              routeName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Chip(
                            label: Text(
                              status.replaceAll('_', ' '),
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
                      const SizedBox(height: 6),
                      Text('$cv / $tv visits completed'),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 20),

          if (_targets.isNotEmpty) ...[
            Text(
              'My Targets',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            ..._targets.map((t) {
              final targetType =
                  t['targetType']?.toString() ?? t['type']?.toString() ?? '--';
              final targetValue =
                  (t['targetValue'] as num?)?.toDouble() ??
                  (t['target'] as num?)?.toDouble() ??
                  0;
              final achieved =
                  (t['achieved'] as num?)?.toDouble() ??
                  (t['achievedValue'] as num?)?.toDouble() ??
                  0;
              final pct = targetValue > 0
                  ? (achieved / targetValue * 100)
                  : 0.0;

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            targetType,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${pct.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: pct >= 90
                                  ? Colors.green
                                  : pct >= 50
                                  ? Colors.orange
                                  : Colors.red,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (pct / 100).clamp(0.0, 1.0),
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_formatCurrency(achieved)} / ${_formatCurrency(targetValue)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  String _formatCurrency(double value) {
    if (value >= 100000) {
      return '₹${(value / 100000).toStringAsFixed(1)}L';
    } else if (value >= 1000) {
      return '₹${(value / 1000).toStringAsFixed(1)}k';
    }
    return '₹${value.toStringAsFixed(0)}';
  }
}
