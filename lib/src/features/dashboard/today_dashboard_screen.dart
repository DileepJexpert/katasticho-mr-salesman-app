import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
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
                initialValue: type,
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

  Widget _attendanceStrip() {
    final punchedIn = _attendance?['punchInAt'] != null;
    final punchedOut = _attendance?['punchOutAt'] != null;
    final color = punchedIn && !punchedOut
        ? Colors.green
        : punchedOut
            ? FieldUi.muted
            : const Color(0xFF2563EB);
    final icon = punchedOut
        ? Icons.task_alt
        : punchedIn
            ? Icons.timer_outlined
            : Icons.badge_outlined;
    final text = punchedOut
        ? 'Day done · in ${_punchTime(_attendance?['punchInAt']?.toString())}'
            ' / out ${_punchTime(_attendance?['punchOutAt']?.toString())}'
        : punchedIn
            ? 'On duty since ${_punchTime(_attendance?['punchInAt']?.toString())}'
            : 'Not punched in yet';

    Widget? punchAction;
    if (!punchedIn) {
      punchAction = FilledButton(
        onPressed: () => _punch(isIn: true),
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        child: const Text('Punch In'),
      );
    } else if (!punchedOut) {
      punchAction = OutlinedButton(
        onPressed: () => _punch(isIn: false),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        child: const Text('Punch Out'),
      );
    }

    return StatusStrip(
      icon: icon,
      text: text,
      color: color,
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (punchAction != null) punchAction,
          IconButton(
            tooltip: 'Apply leave',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.beach_access_outlined),
            onPressed: _applyLeave,
          ),
        ],
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

          _attendanceStrip(),
          const SizedBox(height: 12),

          MetricStrip(
            items: [
              MetricItem('Routes (MTD)', '$totalRoutes',
                  color: const Color(0xFF2563EB)),
              MetricItem('Visits (MTD)', '$totalVisits',
                  color: const Color(0xFF059669)),
              MetricItem('Productive %', '${productivePercent.toStringAsFixed(1)}%',
                  color: const Color(0xFFF59E0B)),
            ],
          ),
          const SizedBox(height: 10),
          MetricStrip(
            items: [
              MetricItem('Orders (MTD)', _formatCurrency(totalOrders),
                  color: const Color(0xFF0891B2)),
              MetricItem('Collections', _formatCurrency(totalCollections),
                  color: const Color(0xFF7C3AED)),
            ],
          ),

          const SectionLabel("Today's Routes"),
          if (_todayExecutions.isEmpty)
            FlatList(
              children: [
                FieldRow(
                  divider: false,
                  leading: Icon(Icons.event_busy, color: Colors.grey.shade400),
                  title: 'No routes assigned for today.',
                ),
              ],
            )
          else
            FlatList(
              children: [
                for (var i = 0; i < _todayExecutions.length; i++)
                  _routeRow(
                    _todayExecutions[i],
                    divider: i != _todayExecutions.length - 1,
                  ),
              ],
            ),

          if (_targets.isNotEmpty) ...[
            const SectionLabel('My Targets'),
            FlatList(
              children: [
                for (var i = 0; i < _targets.length; i++)
                  _targetRow(
                    _targets[i],
                    divider: i != _targets.length - 1,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _routeRow(dynamic exec, {required bool divider}) {
    final routeName = exec['routeName']?.toString() ??
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

    return FieldRow(
      divider: divider,
      title: routeName,
      subtitle: '$cv / $tv visits completed',
      trailing: Chip(
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
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _targetRow(dynamic t, {required bool divider}) {
    final targetType =
        t['targetType']?.toString() ?? t['type']?.toString() ?? '--';
    final targetValue = (t['targetValue'] as num?)?.toDouble() ??
        (t['target'] as num?)?.toDouble() ??
        0;
    final achieved = (t['achieved'] as num?)?.toDouble() ??
        (t['achievedValue'] as num?)?.toDouble() ??
        0;
    final pct = targetValue > 0 ? (achieved / targetValue * 100) : 0.0;
    final pctColor = pct >= 90
        ? Colors.green
        : pct >= 50
            ? Colors.orange
            : Colors.red;

    final row = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 4,
        vertical: FieldUi.gap,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  targetType,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${pct.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: pctColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0.0, 1.0),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_formatCurrency(achieved)} / ${_formatCurrency(targetValue)}',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: FieldUi.muted),
          ),
        ],
      ),
    );
    if (!divider) return row;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [row, const Divider(height: 1)],
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
