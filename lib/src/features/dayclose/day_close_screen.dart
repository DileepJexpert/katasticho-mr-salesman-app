import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
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

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (session?.isDemo == true) {
      return PageScaffold(
        title: 'Day Close',
        subtitle: 'Demo mode — login with real credentials to see live data.',
        children: const [
          StatusStrip(
            icon: Icons.info_outline,
            text:
                'Demo mode shows sample data. Login with your Katasticho ERP '
                'credentials to reconcile and close your day.',
            color: Color(0xFF2563EB),
          ),
        ],
      );
    }

    // When the reconciliation form is showing, pin the submit bar at the
    // bottom. Otherwise the page is a plain scrollable summary.
    final showForm = _execution != null && _dayClose == null;
    final isCompleted =
        _execution?['status']?.toString() == 'COMPLETED';

    final page = RefreshIndicator(
      onRefresh: _load,
      child: PageScaffold(
        title: 'Day Close',
        subtitle: 'End-of-day cash reconciliation and summary.',
        children: [
          if (_error != null) ...[
            StatusStrip(
              icon: Icons.error_outline,
              text: _error!,
              color: Colors.red,
            ),
            const SizedBox(height: 12),
          ],
          if (_execution == null)
            const StatusStrip(
              icon: Icons.event_busy,
              text:
                  'No route execution for today. Start and complete a route '
                  'to close the day.',
              color: FieldUi.muted,
            )
          else ...[
            ..._executionSummary(),
            if (_dayClose != null)
              ..._dayCloseStatus()
            else
              ..._reconciliationForm(isCompleted),
          ],
        ],
      ),
    );

    if (!showForm) return page;

    return Scaffold(
      body: page,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: (!isCompleted || _submitting) ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.nightlight_round),
            label: Text(_submitting ? 'Submitting…' : 'Submit day close'),
          ),
        ),
      ),
    );
  }

  // ── Summary from visits ───────────────────────────────────────

  List<Widget> _executionSummary() {
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

    final statusColor =
        status == 'COMPLETED' ? Colors.green : Colors.orange;

    return [
      SectionLabel(
        routeName,
        trailing: Text(
          status.replaceAll('_', ' '),
          style: TextStyle(
            color: statusColor,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      MetricStrip(items: [
        MetricItem('Visits', '$completed / $totalVisits'),
        MetricItem('Skipped', '$skipped'),
        MetricItem('Orders', _formatCurrency(ordersValue)),
        MetricItem('Collections', _formatCurrency(collections)),
      ]),
    ];
  }

  // ── Day close status (already initiated/submitted) ────────────

  List<Widget> _dayCloseStatus() {
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
      const SizedBox(height: 12),
      StatusStrip(
        icon: bannerIcon,
        text: bannerText,
        color: bannerColor,
      ),
      const SectionLabel('Cash Reconciliation'),
      FlatList(children: [
        _amountRow('Opening cash', dayClose['openingCash']),
        _amountRow('Cash collections', dayClose['cashCollections']),
        _amountRow('Cash expenses', dayClose['cashExpenses']),
        _amountRow('Closing cash', dayClose['closingCash']),
        _amountRow('Cash deposited', dayClose['cashDeposited']),
        _amountRow(
          'Variance',
          dayClose['cashVariance'],
          highlight: true,
          divider: false,
        ),
      ]),
    ];
  }

  Widget _amountRow(
    String label,
    dynamic value, {
    bool highlight = false,
    bool divider = true,
  }) {
    final amount = (value as num?)?.toDouble() ?? 0;
    final color = highlight
        ? (amount == 0 ? Colors.green : Colors.red)
        : FieldUi.ink;
    return FieldRow(
      title: label,
      dense: true,
      divider: divider,
      trailing: Text(
        _formatCurrency(amount),
        style: TextStyle(fontWeight: FontWeight.w800, color: color),
      ),
    );
  }

  // ── Reconciliation form ───────────────────────────────────────

  List<Widget> _reconciliationForm(bool isCompleted) {
    return [
      if (!isCompleted) ...[
        const SizedBox(height: 12),
        StatusStrip(
          icon: Icons.info_outline,
          text: 'Complete your route before closing the day.',
          color: Colors.orange.shade700,
        ),
      ],
      const SectionLabel('Closing cash in hand'),
      TextField(
        controller: _closingCashController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(prefixText: '₹ '),
      ),
      const SectionLabel('Cash deposited'),
      TextField(
        controller: _depositedController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(prefixText: '₹ '),
      ),
      const SectionLabel('Notes'),
      TextField(
        controller: _notesController,
        minLines: 2,
        maxLines: 4,
      ),
    ];
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
