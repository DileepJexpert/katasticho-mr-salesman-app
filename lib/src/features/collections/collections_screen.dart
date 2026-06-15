import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../auth/auth_controller.dart';
import '../shared/field_widgets.dart';

class CollectionsScreen extends ConsumerStatefulWidget {
  const CollectionsScreen({super.key});

  @override
  ConsumerState<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends ConsumerState<CollectionsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _visits = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVisits();
  }

  Future<void> _loadVisits() async {
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

      if (executions.isNotEmpty) {
        final exec = executions[0] as Map<String, dynamic>;
        final execId = exec['id']?.toString();
        if (execId != null) {
          final raw = await api.getVisits(execId);
          if (mounted) {
            setState(() {
              _visits = raw
                  .whereType<Map<String, dynamic>>()
                  .where(
                    (v) =>
                        v['status'] == 'IN_PROGRESS' ||
                        v['status'] == 'COMPLETED',
                  )
                  .toList();
            });
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _recordCollection(String visitId, String contactName) async {
    final amountCtl = TextEditingController();
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Collect from $contactName'),
        content: TextField(
          controller: amountCtl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Amount Collected *',
            prefixText: '₹ ',
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Collection recorded'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _loadVisits();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(authControllerProvider).session;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final collectedCount = _visits
        .where((v) => ((v['collectionAmount'] as num?)?.toDouble() ?? 0) > 0)
        .length;
    final collectedValue = _visits.fold<double>(
      0,
      (sum, v) => sum + ((v['collectionAmount'] as num?)?.toDouble() ?? 0),
    );

    return RefreshIndicator(
      onRefresh: _loadVisits,
      child: PageScaffold(
        title: 'Collections',
        subtitle: 'Record cash and payment collections from today\'s visits.',
        children: [
          if (_error != null) ...[
            StatusStrip(
              icon: Icons.error_outline,
              text: _error!,
              color: Colors.red.shade700,
            ),
            const SizedBox(height: 12),
          ],
          if (session?.isDemo == true)
            StatusStrip(
              icon: Icons.info_outline,
              text: 'Login with real credentials to record collections.',
              color: theme.colorScheme.primary,
            )
          else if (_visits.isEmpty)
            StatusStrip(
              icon: Icons.info_outline,
              text:
                  'Check in to a visit first. Collections can be recorded during or after a visit.',
              color: FieldUi.muted,
            )
          else ...[
            MetricStrip(
              items: [
                MetricItem('Visits', '${_visits.length}'),
                MetricItem('Collected', '$collectedCount'),
                MetricItem(
                  'Amount',
                  '₹${collectedValue.toStringAsFixed(0)}',
                  color: Colors.green,
                ),
              ],
            ),
            const SectionLabel('Visits'),
            FlatList(
              children: [
                for (var i = 0; i < _visits.length; i++)
                  _buildVisitRow(_visits[i], i == _visits.length - 1),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVisitRow(Map<String, dynamic> visit, bool isLast) {
    final visitId = visit['id']?.toString() ?? '';
    final name =
        visit['contactName']?.toString() ??
        visit['contactId']?.toString() ??
        'Customer';
    final status = visit['status']?.toString() ?? '';
    final existing = (visit['collectionAmount'] as num?)?.toDouble();
    final hasCollection = existing != null && existing > 0;

    return FieldRow(
      divider: !isLast,
      title: name,
      subtitle: hasCollection
          ? '${status.replaceAll('_', ' ')} · ₹${existing.toStringAsFixed(0)}'
          : status.replaceAll('_', ' '),
      onTap: () => _recordCollection(visitId, name),
      trailing: FilledButton.icon(
        onPressed: () => _recordCollection(visitId, name),
        icon: const Icon(Icons.payments, size: 16),
        label: Text(hasCollection ? 'Update' : 'Collect'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}
