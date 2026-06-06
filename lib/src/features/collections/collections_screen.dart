import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

    return RefreshIndicator(
      onRefresh: _loadVisits,
      child: PageScaffold(
        title: 'Collections',
        subtitle: 'Record cash and payment collections from today\'s visits.',
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
          if (session?.isDemo == true)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Login with real credentials to record collections.',
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_visits.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.grey.shade400),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Check in to a visit first. Collections can be recorded during or after a visit.',
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._visits.map((visit) {
              final visitId = visit['id']?.toString() ?? '';
              final name =
                  visit['contactName']?.toString() ??
                  visit['contactId']?.toString() ??
                  'Customer';
              final status = visit['status']?.toString() ?? '';
              final existing = (visit['collectionAmount'] as num?)?.toDouble();

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
                              name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            status.replaceAll('_', ' '),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      if (existing != null && existing > 0) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Collected: ₹${existing.toStringAsFixed(0)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: () => _recordCollection(visitId, name),
                        icon: const Icon(Icons.payments, size: 18),
                        label: Text(
                          existing != null && existing > 0
                              ? 'Update Collection'
                              : 'Record Collection',
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
