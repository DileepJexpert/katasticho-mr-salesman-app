import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../shared/field_widgets.dart';

/// Van stock tab: shows the assigned van's current stock, lets the
/// salesperson request a load from a warehouse or return stock, and
/// lists recent LOAD/RETURN transfers.
class VanStockScreen extends ConsumerStatefulWidget {
  const VanStockScreen({super.key});

  @override
  ConsumerState<VanStockScreen> createState() => _VanStockScreenState();
}

class _VanStockScreenState extends ConsumerState<VanStockScreen> {
  bool _loading = true;
  String? _error;
  String? _vanId;
  List<Map<String, dynamic>> _stock = [];
  List<Map<String, dynamic>> _transfers = [];

  static const _lowStockThreshold = 5;

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
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final api = ref.read(apiClientProvider);

      // Find the salesperson's assigned van from active assignments.
      final assignments = await api.getMyAssignments();
      String? vanId;
      for (final raw in assignments) {
        if (raw is Map<String, dynamic>) {
          final id = raw['vanId']?.toString();
          if (id != null && id.isNotEmpty) {
            vanId = id;
            break;
          }
        }
      }

      List<Map<String, dynamic>> stock = [];
      List<Map<String, dynamic>> transfers = [];
      if (vanId != null) {
        final rawStock = await api.getVanStock(vanId);
        stock = rawStock.whereType<Map<String, dynamic>>().toList();
        final rawTransfers = await api.getVanTransfers(vanId);
        transfers = rawTransfers.whereType<Map<String, dynamic>>().toList();
      }

      if (mounted) {
        setState(() {
          _vanId = vanId;
          _stock = stock;
          _transfers = transfers;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Actions ───────────────────────────────────────────────────

  Future<void> _requestLoad() async {
    final vanId = _vanId;
    if (vanId == null) return;

    final request = await _showTransferDialog(
      title: 'Request Load',
      submitLabel: 'Request Load',
      initialItemIds: const [],
    );
    if (request == null || !mounted) return;

    try {
      await ref
          .read(apiClientProvider)
          .createVanLoad(vanId, request.warehouseId, request.lines);
      _showSuccess('Load request created (DRAFT)');
      await _loadData();
    } catch (e) {
      _showError('Failed to create load: $e');
    }
  }

  Future<void> _returnStock() async {
    final vanId = _vanId;
    if (vanId == null) return;

    // Pre-fill the line rows with the item ids currently in van stock.
    final itemIds = _stock
        .map((s) => s['itemId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();

    final request = await _showTransferDialog(
      title: 'Return Stock',
      submitLabel: 'Return',
      initialItemIds: itemIds,
    );
    if (request == null || !mounted) return;

    try {
      await ref
          .read(apiClientProvider)
          .createVanReturn(vanId, request.warehouseId, request.lines);
      _showSuccess('Return request created (DRAFT)');
      await _loadData();
    } catch (e) {
      _showError('Failed to create return: $e');
    }
  }

  /// Shared dialog for load/return: warehouse id + dynamic line rows.
  Future<_TransferRequest?> _showTransferDialog({
    required String title,
    required String submitLabel,
    required List<String> initialItemIds,
  }) async {
    final warehouseCtl = TextEditingController();
    final itemCtls = <TextEditingController>[];
    final qtyCtls = <TextEditingController>[];

    void addRow(String itemId) {
      itemCtls.add(TextEditingController(text: itemId));
      qtyCtls.add(TextEditingController());
    }

    if (initialItemIds.isEmpty) {
      addRow('');
    } else {
      for (final id in initialItemIds) {
        addRow(id);
      }
    }

    final result = await showDialog<_TransferRequest>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: warehouseCtl,
                    decoration: const InputDecoration(
                      labelText: 'Warehouse ID *',
                      hintText: 'Warehouse UUID',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Lines',
                    style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (var i = 0; i < itemCtls.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: itemCtls[i],
                              decoration: const InputDecoration(
                                labelText: 'Item ID',
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: qtyCtls[i],
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Qty',
                                isDense: true,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove line',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: itemCtls.length <= 1
                                ? null
                                : () => setDialogState(() {
                                    itemCtls.removeAt(i);
                                    qtyCtls.removeAt(i);
                                  }),
                          ),
                        ],
                      ),
                    ),
                  TextButton.icon(
                    onPressed: () => setDialogState(() => addRow('')),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add line'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final warehouseId = warehouseCtl.text.trim();
                if (warehouseId.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Warehouse ID is required')),
                  );
                  return;
                }
                final lines = <Map<String, dynamic>>[];
                for (var i = 0; i < itemCtls.length; i++) {
                  final itemId = itemCtls[i].text.trim();
                  final qty = double.tryParse(qtyCtls[i].text.trim());
                  if (itemId.isEmpty || qty == null || qty <= 0) continue;
                  lines.add({'itemId': itemId, 'quantity': qty});
                }
                if (lines.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'At least one line with item ID and quantity is required',
                      ),
                    ),
                  );
                  return;
                }
                Navigator.pop(
                  ctx,
                  _TransferRequest(warehouseId: warehouseId, lines: lines),
                );
              },
              child: Text(submitLabel),
            ),
          ],
        ),
      ),
    );
    return result;
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

  // ── UI ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).session;
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (session?.isDemo == true) {
      return const PageScaffold(
        title: 'Van Stock',
        subtitle: 'Demo mode — login to see your van stock.',
        children: [],
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: PageScaffold(
        title: 'Van Stock',
        subtitle: 'Stock on your assigned van, loads and returns.',
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

          if (_vanId == null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.local_shipping, color: Colors.grey.shade400),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'No van assigned to you. Ask your admin to set up a '
                        'field sales assignment with a van.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _requestLoad,
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Request Load'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _stock.isEmpty ? null : _returnStock,
                    icon: const Icon(Icons.upload, size: 18),
                    label: const Text('Return Stock'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Current stock
            Text(
              'Current Stock',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            if (_stock.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('Van is empty. Request a load to begin.'),
                ),
              )
            else
              ..._stock.map((row) => _buildStockCard(row, theme)),
            const SizedBox(height: 16),

            // Recent transfers
            Text(
              'Recent Transfers',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            if (_transfers.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('No transfers yet.'),
                ),
              )
            else
              ..._transfers.map((t) => _buildTransferCard(t, theme)),
          ],
        ],
      ),
    );
  }

  Widget _buildStockCard(Map<String, dynamic> row, ThemeData theme) {
    final itemId = row['itemId']?.toString() ?? '';
    final itemLabel =
        row['itemName']?.toString() ??
        row['itemCode']?.toString() ??
        (itemId.length > 8 ? 'Item ${itemId.substring(0, 8)}…' : 'Item');
    final qty = (row['quantityOnHand'] as num?)?.toDouble() ?? 0;
    final lowStock = qty <= _lowStockThreshold;
    final qtyColor = lowStock ? Colors.red : Colors.green.shade700;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.inventory_2,
              size: 20,
              color: lowStock ? Colors.red : theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    itemLabel,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (itemId.isNotEmpty)
                    Text(
                      itemId,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 2),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: qtyColor,
                  ),
                ),
                if (lowStock)
                  Text(
                    'Low stock',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransferCard(Map<String, dynamic> transfer, ThemeData theme) {
    final type = transfer['transferType']?.toString() ?? 'LOAD';
    final status = transfer['status']?.toString() ?? 'DRAFT';
    final date = transfer['transferDate']?.toString() ?? '';

    final isLoad = type == 'LOAD';
    final typeColor = isLoad ? const Color(0xFF0891B2) : const Color(0xFFF59E0B);
    final statusColor = switch (status) {
      'CONFIRMED' => Colors.green,
      'CANCELLED' => Colors.red,
      _ => Colors.blueGrey,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              isLoad ? Icons.download : Icons.upload,
              size: 20,
              color: typeColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (date.isNotEmpty)
                    Text(date, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            Chip(
              label: Text(
                status,
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
      ),
    );
  }
}

class _TransferRequest {
  const _TransferRequest({required this.warehouseId, required this.lines});

  final String warehouseId;
  final List<Map<String, dynamic>> lines;
}
