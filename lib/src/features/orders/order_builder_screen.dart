import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/auth_controller.dart';

/// Builds a real line-item Sales Order or Pharma POB against the ERP catalog.
///
/// Flow:
/// - Search catalog items -> add to cart -> adjust quantity & rate
/// - For Chemists / Pharma: select preferred Supplying Stockist -> books Chemist POB
///   with 1-click WhatsApp consolidated supply advice to stockist.
/// - For general customers / distributors: creates standard ERP Sales Order.
/// - Links to field visit when visitId is present.
class OrderBuilderScreen extends ConsumerStatefulWidget {
  const OrderBuilderScreen({
    super.key,
    this.visitId = '',
    required this.contactId,
    required this.contactName,
    this.medicalCategory,
  });

  final String visitId;
  final String contactId;
  final String contactName;
  final String? medicalCategory;

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
  final List<_CartLine> _removedLines = [];
  bool _submitting = false;

  // Pharma Stockist Selection
  String? _selectedStockistId;
  String? _selectedStockistName;
  List<Map<String, dynamic>> _stockists = [];

  @override
  void initState() {
    super.initState();
    _searchCtl.addListener(_onSearchChanged);
    _loadStockists();
    _runSearch('');
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

  Future<void> _loadStockists() async {
    final medCat = widget.medicalCategory?.toUpperCase();
    final isChemistOrPharma = medCat == 'CHEMIST' ||
        medCat == 'RETAILER' ||
        ref.read(authControllerProvider).session?.isPharma == true;

    if (!isChemistOrPharma) return;

    try {
      final contacts = await ref.read(apiClientProvider).getContacts();
      final stockists = contacts.whereType<Map<String, dynamic>>().where((c) {
        final cat = c['medicalCategory']?.toString().toUpperCase();
        return cat == 'STOCKIST' || cat == 'DISTRIBUTOR';
      }).toList();

      if (mounted) {
        setState(() {
          _stockists = stockists;
          if (stockists.isNotEmpty) {
            _selectedStockistId = stockists.first['id']?.toString();
            _selectedStockistName = stockists.first['displayName']?.toString();
          }
        });
      }
    } catch (_) {}
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    final query = _searchCtl.text.trim();
    _debounce = Timer(const Duration(milliseconds: 300), () {
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

    // ── PATH 1: Pharma Chemist POB Order ─────────────────────────
    if (_selectedStockistId != null && _selectedStockistId!.isNotEmpty) {
      try {
        final pobLines = _cart
            .map((line) => <String, dynamic>{
                  'itemId': line.itemId,
                  'quantity': line.quantity,
                  'rate': line.effectiveRate,
                })
            .toList();

        final todayStr = DateTime.now().toIso8601String().split('T')[0];
        final pob = await api.createPharmaPob(
          chemistId: widget.contactId,
          stockistId: _selectedStockistId!,
          orderDate: todayStr,
          fieldVisitId: widget.visitId.isNotEmpty ? widget.visitId : null,
          notes: 'Field POB — ${widget.contactName}',
          lines: pobLines,
        );

        final pobNumber = pob['orderNumber']?.toString() ?? 'POB';
        final totalAmount = (pob['totalAmount'] as num?)?.toDouble() ?? _grandTotal;

        if (widget.visitId.isNotEmpty) {
          try {
            await api.recordOrder(
              widget.visitId,
              salesOrderId: pobNumber,
              orderValue: totalAmount,
            );
          } catch (_) {}
        }

        if (!mounted) return;
        setState(() => _submitting = false);

        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Color(0xFF059669)),
                SizedBox(width: 8),
                Text('POB Booked!'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Order Number: $pobNumber',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text('Chemist: ${widget.contactName}'),
                Text('Supplying Stockist: ${_selectedStockistName ?? 'Stockist'}'),
                Text(
                  'Total Value: ${_money(totalAmount)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Send the consolidated supply advice to this stockist via WhatsApp.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                icon: const Icon(Icons.share, size: 16),
                label: const Text('WhatsApp Stockist'),
                onPressed: () async {
                  try {
                    final advice = await api.getStockistSupplyAdvice(_selectedStockistId!);
                    final shareText = advice['shareableWhatsAppText']?.toString() ??
                        'POB Order $pobNumber booked for ${widget.contactName} - Value: ${_money(totalAmount)}';
                    final encoded = Uri.encodeComponent(shareText);
                    final uri = Uri.parse('https://wa.me/?text=$encoded');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  } catch (_) {
                    final fallback =
                        'POB Order $pobNumber booked for ${widget.contactName} (Value: ${_money(totalAmount)}). Please dispatch.';
                    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(fallback)}');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
            ],
          ),
        );

        if (mounted) Navigator.of(context).pop(true);
        return;
      } catch (e) {
        if (mounted) {
          setState(() => _submitting = false);
          String message = e.toString();
          if (e is DioException && e.response?.data is Map) {
            final data = e.response!.data as Map;
            message = data['message']?.toString() ?? data['error']?.toString() ?? message;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('POB Booking failed: $message'),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
        return;
      }
    }

    // ── PATH 2: Standard ERP Sales Order ─────────────────────────
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
        notes: widget.visitId.isNotEmpty
            ? 'Field visit order — ${widget.contactName}'
            : 'Field order — ${widget.contactName}',
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

    // Link the created SO to the visit if on a visit.
    if (widget.visitId.isNotEmpty) {
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

  Future<void> _showQuickAmountDialog() async {
    if (widget.visitId.isEmpty) return;
    final valueCtl = TextEditingController();
    final soIdCtl = TextEditingController();
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quick Order Value'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Record a lump-sum order value quickly (works offline).',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [2500, 5000, 10000, 15000, 25000].map((amt) {
                return ActionChip(
                  label: Text('₹$amt', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () => valueCtl.text = '$amt',
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: valueCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Order Value (₹) *',
                prefixText: '₹ ',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: soIdCtl,
              decoration: const InputDecoration(
                labelText: 'Ref / POB Note (Optional)',
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
              if (valueCtl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Save Order Value'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    final val = double.tryParse(valueCtl.text.trim()) ?? 0;
    try {
      await ref.read(apiClientProvider).recordOrder(
            widget.visitId,
            salesOrderId: soIdCtl.text.trim(),
            orderValue: val,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order value ${_money(val)} recorded!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalUnits = _cart.fold<int>(0, (s, l) => s + l.quantity);

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
                  'No customer linked to this order.\n'
                  'Select a party from the Parties list.',
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
            Text(
              _selectedStockistId != null ? 'Chemist POB Booking' : 'Build Order',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            Text(
              widget.contactName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        actions: [
          if (widget.visitId.isNotEmpty)
            TextButton.icon(
              onPressed: _showQuickAmountDialog,
              icon: const Icon(Icons.bolt, size: 16, color: Color(0xFF0B6B5E)),
              label: const Text(
                'Quick ₹',
                style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0B6B5E)),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Preferred Supplying Stockist Selector (for Pharma POB)
          if (_stockists.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warehouse_outlined, size: 20, color: Color(0xFF0B6B5E)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _selectedStockistId,
                        hint: const Text('Select Supplying Stockist (POB)'),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Direct Company Order (No Stockist)'),
                          ),
                          ..._stockists.map((s) {
                            final id = s['id']?.toString() ?? '';
                            final name = s['displayName']?.toString() ?? 'Stockist';
                            return DropdownMenuItem(
                              value: id,
                              child: Text(
                                'Stockist: $name',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            );
                          }),
                        ],
                        onChanged: (val) {
                          setState(() {
                            _selectedStockistId = (val != null && val.isNotEmpty) ? val : null;
                            if (_selectedStockistId != null) {
                              final match = _stockists.firstWhere(
                                (s) => s['id']?.toString() == val,
                                orElse: () => {},
                              );
                              _selectedStockistName = match['displayName']?.toString();
                            } else {
                              _selectedStockistName = null;
                            }
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Search catalog items
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchCtl,
              decoration: InputDecoration(
                hintText: 'Filter medicines & products by brand or SKU…',
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

          // Live Cart Summary Pill Strip
          if (_cart.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shopping_bag, size: 16, color: Color(0xFF10B981)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_cart.length} Brand${_cart.length == 1 ? '' : 's'} ($totalUnits units) in Cart · ${_money(_grandTotal)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _removedLines.addAll(_cart);
                        _cart.clear();
                      });
                    },
                    child: const Text(
                      'Clear',
                      style: TextStyle(
                        color: Color(0xFFFCA5A5),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
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
                      child: Text('No items found matching search.'),
                    ),
                  ),
                ..._results.map((item) => _buildResultTile(item, theme)),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
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
                    Text(
                      _cart.isEmpty
                          ? 'Tap + ADD on any product'
                          : '${_cart.length} brands · $totalUnits units',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    Text(
                      _money(_grandTotal),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0B6B5E),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _cart.isEmpty || _submitting ? null : _placeOrder,
                icon: _submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_circle_outline, size: 20),
                label: Text(
                  _submitting
                      ? 'Booking…'
                      : _selectedStockistId != null
                          ? 'Book POB & Share'
                          : 'Place Order',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultTile(Map<String, dynamic> item, ThemeData theme) {
    final itemId = item['id']?.toString() ?? '';
    final name = item['name']?.toString() ?? 'Item';
    final sku = item['sku']?.toString();
    final salePrice = (item['salePrice'] as num?)?.toDouble() ?? 0;
    final onHand = (item['totalOnHand'] as num?)?.toDouble();
    final trackInventory = item['trackInventory'] == true;

    final cartLine = _cart.where((l) => l.itemId == itemId).firstOrNull;
    final inCart = cartLine != null;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: inCart ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
          width: inCart ? 1.5 : 1.0,
        ),
      ),
      color: inCart ? const Color(0xFFF0FDF4) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (sku != null && sku.isNotEmpty) sku,
                          'PTR: ${_money(salePrice)}',
                          if (trackInventory && onHand != null)
                            '${onHand.toStringAsFixed(0)} in stock',
                        ].join(' · '),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!inCart)
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFECFDF5),
                      foregroundColor: const Color(0xFF0B6B5E),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: Color(0xFFA7F3D0)),
                      ),
                    ),
                    onPressed: () => _addToCart(item),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text(
                      'ADD',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B6B5E),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () => _changeQty(cartLine, -1),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            child: Icon(Icons.remove, size: 16, color: Colors.white),
                          ),
                        ),
                        Text(
                          '${cartLine.quantity}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        InkWell(
                          onTap: () => _changeQty(cartLine, 1),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            child: Icon(Icons.add, size: 16, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (inCart) ...[
              const SizedBox(height: 8),
              const Divider(height: 1, color: Color(0xFFBBF7D0)),
              const SizedBox(height: 8),
              Row(
                children: [
                  // Quick pack quantity chips
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _packChip('+5', () => _changeQty(cartLine, 5)),
                        _packChip('+10', () => _changeQty(cartLine, 10)),
                        _packChip('+20', () => _changeQty(cartLine, 20)),
                        _packChip('10+2 Box', () {
                          setState(() => cartLine.quantity = 10);
                        }),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 86,
                    child: TextField(
                      controller: cartLine.rateCtl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        labelText: 'Rate ₹',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _money(cartLine.lineTotal),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: Color(0xFF065F46),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _packChip(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF86EFAC)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF047857),
          ),
        ),
      ),
    );
  }
}
