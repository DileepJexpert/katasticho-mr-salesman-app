import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../shared/field_widgets.dart';
import 'order_builder_screen.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
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

  /// Record Order entry point: bottom sheet with two paths —
  /// build a real line-item Sales Order, or the quick-amount dialog.
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
          ),
        ),
      );
      if (placed == true && mounted) await _loadVisits();
    } else {
      await _recordOrder(visitId, contactName);
    }
  }

  Future<void> _recordOrder(String visitId, String contactName) async {
    final valueCtl = TextEditingController();
    final soIdCtl = TextEditingController();
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Order for $contactName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: soIdCtl,
              decoration: const InputDecoration(
                labelText: 'Sales Order ID',
                hintText: 'Optional — leave blank for quick order',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: valueCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Order Value *',
                prefixText: '₹ ',
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
            child: const Text('Record Order'),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order recorded'),
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
        title: 'Orders',
        subtitle: 'Record orders against active or completed visits.',
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
                        'Login with real credentials to record orders.',
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
                        'Check in to a visit first. Orders can be recorded during or after a visit.',
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._visits.map((visit) {
              final name =
                  visit['contactName']?.toString() ??
                  visit['contactId']?.toString() ??
                  'Customer';
              final status = visit['status']?.toString() ?? '';
              final existingOrder = (visit['orderValue'] as num?)?.toDouble();

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
                      if (existingOrder != null && existingOrder > 0) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Current order: ₹${existingOrder.toStringAsFixed(0)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: () => _showOrderOptions(visit),
                        icon: const Icon(Icons.add_shopping_cart, size: 18),
                        label: Text(
                          existingOrder != null && existingOrder > 0
                              ? 'Update Order'
                              : 'Record Order',
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
