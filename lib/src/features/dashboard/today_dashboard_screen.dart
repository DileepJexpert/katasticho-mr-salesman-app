import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  String? _error;

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
