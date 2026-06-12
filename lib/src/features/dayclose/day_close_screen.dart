import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../shared/field_widgets.dart';

class DayCloseScreen extends ConsumerStatefulWidget {
  const DayCloseScreen({super.key});

  @override
  ConsumerState<DayCloseScreen> createState() => _DayCloseScreenState();
}

class _DayCloseScreenState extends ConsumerState<DayCloseScreen> {
  final _closingCashController = TextEditingController();
  final _depositedController = TextEditingController();
  final _notesController = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  String? _error;

  Map<String, dynamic>? _execution;
  List<dynamic> _visits = [];
  Map<String, dynamic>? _dayClose;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _closingCashController.dispose();
    _depositedController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final session = ref.read(authControllerProvider).session;
    if (session == null || session.isDemo) {
      setState(() => _loading = false);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final executions = await api.getMyTodayExecutions();

      Map<String, dynamic>? execution;
      for (final status in ['COMPLETED', 'IN_PROGRESS']) {
        for (final raw in executions) {
          if (raw is Map<String, dynamic> &&
              raw['status']?.toString() == status) {
            execution = raw;
            break;
          }
        }
        if (execution != null) break;
      }

      List<dynamic> visits = [];
      Map<String, dynamic>? dayClose;
      if (execution != null) {
        final execId = execution['id']?.toString() ?? '';
        visits = await api.getVisits(execId);

        final dayCloseId = execution['dayCloseId']?.toString();
        if (dayCloseId != null && dayCloseId.isNotEmpty) {
          dayClose = await api.getDayClose(dayCloseId);
        }
      }

      if (mounted) {
        setState(() {
          _execution = execution;
          _visits = visits;
          _dayClose = dayClose;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final execution = _execution;
    if (execution == null) return;

    final closingCash = double.tryParse(_closingCashController.text.trim());
    if (closingCash == null || closingCash < 0) {
      _showSnack('Enter the closing cash amount.');
      return;
    }
    final deposited =
        double.tryParse(_depositedController.text.trim()) ?? 0;

    setState(() => _submitting = true);
    try {
      final api = ref.read(apiClientProvider);
      final execId = execution['id']?.toString() ?? '';
      final initiated = await api.initiateDayClose(execId);
      final dayCloseId = initiated['id']?.toString() ?? '';
      final submitted = await api.submitDayClose(
        dayCloseId,
        closingCash: closingCash,
        cashDeposited: deposited,
        notes: _notesController.text.trim(),
      );
      if (mounted) {
        setState(() => _dayClose = submitted);
        _showSnack('Day close submitted for approval.');
      }
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 409) {
        _showSnack('A day close already exists for this route.');
      } else {
        _showSnack('Day close failed: ${e.message ?? e}');
      }
    } catch (e) {
      if (mounted) _showSnack('Day close failed: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
        title: 'Day Close',
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
                      'Demo mode shows sample data. Login with your '
                      'Katasticho ERP credentials to reconcile and close '
                      'your day.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: PageScaffold(
        title: 'Day Close',
        subtitle: 'End-of-day cash reconciliation and summary.',
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
          if (_execution == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.event_busy, color: Colors.grey.shade400),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'No route execution for today. Start and complete '
                        'a route to close the day.',
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            _executionSummary(theme),
            const SizedBox(height: 16),
            if (_dayClose != null)
              ..._dayCloseStatus(theme)
            else
              _reconciliationForm(theme),
          ],
        ],
      ),
    );
  }

  // ── Summary from visits ───────────────────────────────────────

  Widget _executionSummary(ThemeData theme) {
    final execution = _execution!;
    final routeName =
        execution['routeName']?.toString() ??
        execution['routeId']?.toString() ??
        'Route';
    final status = execution['status']?.toString() ?? '';

    final totalVisits = _visits.length;
    var completed = 0;
    var skipped = 0;
    var ordersValue = 0.0;
    var collections = 0.0;
    for (final raw in _visits) {
      if (raw is! Map<String, dynamic>) continue;
      final visitStatus = raw['status']?.toString() ?? '';
      if (visitStatus == 'COMPLETED') completed++;
      if (visitStatus == 'SKIPPED') skipped++;
      ordersValue += (raw['orderValue'] as num?)?.toDouble() ?? 0;
      collections += (raw['collectionAmount'] as num?)?.toDouble() ?? 0;
    }

    return Column(
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
                  color: status == 'COMPLETED' ? Colors.green : Colors.orange,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              backgroundColor:
                  (status == 'COMPLETED' ? Colors.green : Colors.orange)
                      .withValues(alpha: 0.1),
              side: BorderSide.none,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: MetricTile(
                icon: Icons.storefront,
                label: 'Visits',
                value: '$completed / $totalVisits',
                tint: const Color(0xFF2563EB),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MetricTile(
                icon: Icons.skip_next,
                label: 'Skipped',
                value: '$skipped',
                tint: const Color(0xFF475569),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: MetricTile(
                icon: Icons.shopping_cart,
                label: 'Orders',
                value: _formatCurrency(ordersValue),
                tint: const Color(0xFF0891B2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MetricTile(
                icon: Icons.payments,
                label: 'Collections',
                value: _formatCurrency(collections),
                tint: const Color(0xFF7C3AED),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Day close status (already initiated/submitted) ────────────

  List<Widget> _dayCloseStatus(ThemeData theme) {
    final dayClose = _dayClose!;
    final status = dayClose['status']?.toString() ?? 'PENDING';

    final (bannerColor, bannerIcon, bannerText) = switch (status) {
      'APPROVED' => (
        Colors.green,
        Icons.check_circle,
        'Day close approved.',
      ),
      'REJECTED' => (
        Colors.red,
        Icons.cancel,
        'Day close rejected.'
            '${dayClose['rejectionReason'] != null ? ' Reason: ${dayClose['rejectionReason']}' : ''}',
      ),
      'SUBMITTED' => (
        Colors.amber.shade800,
        Icons.hourglass_top,
        'Day close submitted — awaiting approval.',
      ),
      _ => (
        Colors.blueGrey,
        Icons.pending_actions,
        'Day close initiated but not yet submitted.',
      ),
    };

    return [
      Card(
        color: bannerColor.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(bannerIcon, color: bannerColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  bannerText,
                  style: TextStyle(
                    color: bannerColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        'Cash Reconciliation',
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              _amountRow('Opening cash', dayClose['openingCash']),
              _amountRow('Cash collections', dayClose['cashCollections']),
              _amountRow('Cash expenses', dayClose['cashExpenses']),
              const Divider(),
              _amountRow('Closing cash', dayClose['closingCash']),
              _amountRow('Cash deposited', dayClose['cashDeposited']),
              _amountRow(
                'Variance',
                dayClose['cashVariance'],
                highlight: true,
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _amountRow(String label, dynamic value, {bool highlight = false}) {
    final amount = (value as num?)?.toDouble() ?? 0;
    final color = highlight
        ? (amount == 0 ? Colors.green : Colors.red)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Text(
            _formatCurrency(amount),
            style: TextStyle(fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }

  // ── Reconciliation form ───────────────────────────────────────

  Widget _reconciliationForm(ThemeData theme) {
    final execution = _execution!;
    final isCompleted = execution['status']?.toString() == 'COMPLETED';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cash Reconciliation',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                if (!isCompleted) ...[
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Complete your route before closing the day.',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _closingCashController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Closing cash in hand',
                    prefixText: '₹ ',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _depositedController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Cash deposited',
                    prefixText: '₹ ',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notesController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: (!isCompleted || _submitting) ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.nightlight_round),
                    label: Text(
                      _submitting ? 'Submitting…' : 'Submit day close',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
