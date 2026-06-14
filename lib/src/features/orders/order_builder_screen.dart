import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';

/// Builds a real line-item Sales Order against the ERP catalog and links
/// it to the field visit.
///
/// Flow: search items → build cart → POST /api/v1/sales-orders →
/// acknowledge any warnings (SO is already created at that point) →
/// record-order on the visit with the real salesOrderId + totalAmount.
///
/// SO creation is intentionally NOT offline-queued — use the "Quick
/// amount" option (which queues offline) when there is no connectivity.
class OrderBuilderScreen extends ConsumerStatefulWidget {
  const OrderBuilderScreen({
    super.key,
    required this.visitId,
    required this.contactId,
    required this.contactName,
  });

  final String visitId;
  final String contactId;
  final String contactName;

  @override
  ConsumerState<OrderBuilderScreen> createState() => _OrderBuilderScreenState();
}

class _CartLine {
  _CartLine({
    required this.itemId,
    required this.name,
    this.sku,
    this.taxGroupId,
    this.hsnCode,
    required this.rate,
  }) : quantity = 1, rateCtl = TextEditingController(text: _trimZeros(rate));

  final String itemId;
  final String name;
  final String? sku;
  final String? taxGroupId;
  final String? hsnCode;
  double rate;
  int quantity;
  final TextEditingController rateCtl;

  double get effectiveRate => double.tryParse(rateCtl.text.trim()) ?? rate;
  double get lineTotal => effectiveRate * quantity;

  static String _trimZeros(double v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('.00') ? v.toStringAsFixed(0) : s;
  }

  void dispose() => rateCtl.dispose();
}

class _OrderBuilderScreenState extends ConsumerState<OrderBuilderScreen> {
  final _searchCtl = TextEditingController();
  Timer? _debounce;
  bool _searching = false;
  List<Map<String, dynamic>> _results = [];
  String? _searchError;

  final List<_CartLine> _cart = [];
  // Controllers of removed cart lines — disposed with the screen so we
  // never dispose a controller whose TextField may still be in the tree.
  final List<_CartLine> _removedLines = [];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _searchCtl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtl.removeListener(_onSearchChanged);
    _searchCtl.dispose();
    for (final line in _cart) {
      line.dispose();
    }
    for (final line in _removedLines) {
      line.dispose();
    }
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    final query = _searchCtl.text.trim();
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _searching = false;
        _searchError = null;
      });
      return;
    }
    // Rebuild so the clear (suffix) icon tracks the text state.
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _runSearch(query);
    });
  }

  Future<void> _runSearch(String query) async {
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final raw = await ref.read(apiClientProvider).searchItems(query);
      if (!mounted || _searchCtl.text.trim() != query) return;
      setState(() {
        _results = raw.whereType<Map<String, dynamic>>().toList();
      });
    } catch (e) {
      if (mounted && _searchCtl.text.trim() == query) {
        setState(() => _searchError = 'Search failed: $e');
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _addToCart(Map<String, dynamic> item) {
    final itemId = item['id']?.toString();
    if (itemId == null || itemId.isEmpty) return;

    setState(() {
      final existing = _cart.where((l) => l.itemId == itemId).toList();
      if (existing.isNotEmpty) {
        existing.first.quantity += 1;
      } else {
        _cart.add(
          _CartLine(
            itemId: itemId,
            name: item['name']?.toString() ?? 'Item',
            sku: item['sku']?.toString(),
            taxGroupId: item['defaultTaxGroupId']?.toString(),
            hsnCode: item['hsnCode']?.toString(),
            rate: (item['salePrice'] as num?)?.toDouble() ?? 0,
          ),
        );
      }
    });
  }

  void _changeQty(_CartLine line, int delta) {
    setState(() {
      line.quantity += delta;
      if (line.quantity <= 0) {
        _cart.remove(line);
        _removedLines.add(line);
      }
    });
  }

  double get _grandTotal =>
      _cart.fold(0.0, (sum, line) => sum + line.lineTotal);

  String _money(double v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('.00') ? '₹${v.toStringAsFixed(0)}' : '₹$s';
  }

  bool _isNetworkError(Object e) {
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return true;
        default:
          break;
      }
    }
    final text = e.toString();
    return text.contains('SocketException') ||
        text.contains('Connection refused') ||
        text.contains('Network is unreachable') ||
        text.contains('Failed host lookup');
  }

  Future<void> _placeOrder() async {
    if (_cart.isEmpty || _submitting) return;

    // Validate rates before submitting.
    for (final line in _cart) {
      final rate = double.tryParse(line.rateCtl.text.trim());
      if (rate == null || rate < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid rate for ${line.name}')),
        );
        return;
      }
    }

    setState(() => _submitting = true);
    final api = ref.read(apiClientProvider);

    final lines = _cart
        .map(
          (line) => <String, dynamic>{
            'itemId': line.itemId,
            'description': line.name,
            'quantity': line.quantity,
            'rate': line.effectiveRate,
            'discountPct': 0,
            if (line.taxGroupId != null && line.taxGroupId!.isNotEmpty)
              'taxGroupId': line.taxGroupId,
            if (line.hsnCode != null && line.hsnCode!.isNotEmpty)
              'hsnCode': line.hsnCode,
          },
        )
        .toList();

    Map<String, dynamic> so;
    try {
      so = await api.createSalesOrder(
        contactId: widget.contactId,
        lines: lines,
        notes: 'Field visit order — ${widget.contactName}',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isNetworkError(e)
                  ? 'No connection — use the Quick amount option to record '
                        'the order offline.'
                  : 'Order failed: $e',
            ),
            backgroundColor: _isNetworkError(e) ? Colors.orange : null,
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    // Warnings arrive ON the create response, AFTER the SO already exists,
    // so this is an acknowledge-only dialog (no Cancel — that would orphan
    // the created SO).
    final warnings = (so['warnings'] as List?)
        ?.map((w) => w.toString())
        .where((w) => w.isNotEmpty)
        .toList();
    if (warnings != null && warnings.isNotEmpty) {
      final status = so['status']?.toString();
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(
            status == 'PENDING_APPROVAL'
                ? 'Order needs approval'
                : 'Order created with warnings',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: warnings
                .map(
                  (w) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(w)),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (!mounted) return;
    }

    final soId = so['id']?.toString() ?? '';
    final soNumber = so['salesOrderNumber']?.toString() ?? '';
    final totalAmount = (so['totalAmount'] as num?)?.toDouble() ?? _grandTotal;

    // Link the created SO to the visit.
    try {
      await api.recordOrder(
        widget.visitId,
        salesOrderId: soId,
        orderValue: totalAmount,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Order $soNumber created, but linking it to the visit failed: '
              '$e',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.of(context).pop(true);
      }
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          soNumber.isNotEmpty
              ? 'Order $soNumber placed — ${_money(totalAmount)}'
              : 'Order placed — ${_money(totalAmount)}',
        ),
        backgroundColor: Colors.green,
      ),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.contactId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Build Order')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_off, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                const Text(
                  'No customer linked to this visit.\n'
                  'Use the Quick amount option instead.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Build Order'),
            Text(
              widget.contactName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchCtl,
              decoration: InputDecoration(
                hintText: 'Search items by name or SKU…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchCtl.clear(),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
              textInputAction: TextInputAction.search,
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                if (_searching)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (_searchError != null)
                  Card(
                    color: Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        _searchError!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  ),
                if (!_searching &&
                    _searchError == null &&
                    _searchCtl.text.trim().isNotEmpty &&
                    _results.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Text('No items found.'),
                    ),
                  ),
                ..._results.map((item) => _buildResultTile(item, theme)),

                if (_cart.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Cart (${_cart.length} item${_cart.length == 1 ? '' : 's'})',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ..._cart.map((line) => _buildCartLine(line, theme)),
                ] else if (_searchCtl.text.trim().isEmpty) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(
                            Icons.shopping_cart_outlined,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Search the catalog above and tap an item to '
                              'add it to the cart.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Total', style: theme.textTheme.bodySmall),
                    Text(
                      _money(_grandTotal),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _cart.isEmpty || _submitting ? null : _placeOrder,
                icon: _submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline, size: 20),
                label: Text(_submitting ? 'Placing…' : 'Place Order'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultTile(Map<String, dynamic> item, ThemeData theme) {
    final name = item['name']?.toString() ?? 'Item';
    final sku = item['sku']?.toString();
    final salePrice = (item['salePrice'] as num?)?.toDouble() ?? 0;
    final onHand = (item['totalOnHand'] as num?)?.toDouble();
    final trackInventory = item['trackInventory'] == true;
    final inCart = _cart.any((l) => l.itemId == item['id']?.toString());

    return Card(
      child: ListTile(
        dense: true,
        title: Text(
          name,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          [
            if (sku != null && sku.isNotEmpty) sku,
            _money(salePrice),
            if (trackInventory && onHand != null)
              '${onHand.toStringAsFixed(onHand == onHand.roundToDouble() ? 0 : 1)} on hand',
          ].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
        trailing: Icon(
          inCart ? Icons.add_circle : Icons.add_circle_outline,
          color: theme.colorScheme.primary,
        ),
        onTap: () => _addToCart(item),
      ),
    );
  }

  Widget _buildCartLine(_CartLine line, ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    line.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  _money(line.lineTotal),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // Qty stepper
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    line.quantity == 1
                        ? Icons.delete_outline
                        : Icons.remove_circle_outline,
                    size: 22,
                    color: line.quantity == 1
                        ? Colors.red
                        : theme.colorScheme.primary,
                  ),
                  onPressed: () => _changeQty(line, -1),
                ),
                SizedBox(
                  width: 32,
                  child: Text(
                    '${line.quantity}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.add_circle_outline,
                    size: 22,
                    color: theme.colorScheme.primary,
                  ),
                  onPressed: () => _changeQty(line, 1),
                ),
                const Spacer(),
                // Editable rate
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: line.rateCtl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      labelText: 'Rate',
                      prefixText: '₹ ',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
