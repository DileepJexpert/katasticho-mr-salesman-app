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

          final visits = raw
              .whereType<Map>()
              .map((v) => Map<String, dynamic>.from(v))
              .where(
                (v) =>
                    v['status'] == 'IN_PROGRESS' ||
                    v['status'] == 'COMPLETED',
              )
              .toList();

          for (final v in visits) {
            final cid = v['contactId']?.toString();
            if (cid != null && contactMap.containsKey(cid)) {
              final c = contactMap[cid]!;
              v['contactName'] ??= c['displayName'];
              v['contactPhone'] ??= c['phone'];
              v['medicalCategory'] ??= c['medicalCategory'];
              v['city'] ??= c['billingCity'];
            }
          }

          if (mounted) {
            setState(() {
              _visits = visits;
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
    String paymentMethod = 'CASH';
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Collect from $contactName'),
        content: StatefulBuilder(
          builder: (ctx, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtl,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Amount Collected *',
                  prefixText: '₹ ',
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

    try {
      await ref
          .read(apiClientProvider)
          .recordCollection(
            visitId,
            collectionAmount: double.tryParse(amountCtl.text.trim()) ?? 0,
            paymentMethod: paymentMethod,
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
              final category = visit['medicalCategory']?.toString();
              final city = visit['city']?.toString();
              final phone = visit['contactPhone']?.toString();
              final subtitleParts = [
                if (category != null && category.isNotEmpty) category,
                if (city != null && city.isNotEmpty) city,
                if (phone != null && phone.isNotEmpty) phone,
              ];

              final isCompleted = status == 'COMPLETED';

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (subtitleParts.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitleParts.join(' · '),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isCompleted
                                  ? Colors.green.shade50
                                  : Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isCompleted
                                  ? Colors.green.shade200
                                  : Colors.amber.shade200,
                              ),
                            ),
                            child: Text(
                              status.replaceAll('_', ' '),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isCompleted
                                    ? Colors.green.shade800
                                    : Colors.amber.shade900,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (existing != null && existing > 0) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Collected: ₹${existing.toStringAsFixed(0)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w700,
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
