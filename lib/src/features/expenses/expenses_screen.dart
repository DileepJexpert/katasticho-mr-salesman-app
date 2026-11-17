import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../auth/auth_controller.dart';
import '../shared/field_widgets.dart';

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  static const _categories = ['TRAVEL', 'FOOD', 'LODGING', 'MISC'];

  String _category = 'TRAVEL';
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  XFile? _receipt;

  bool _loading = true;
  bool _submitting = false;
  String? _error;
  List<dynamic> _expenses = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String get _today => DateTime.now().toIso8601String().split('T')[0];

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
      final expenses = await api.getReimbursements();
      if (mounted) {
        setState(() {
          _expenses = expenses;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      _showSnack('Enter a valid amount.');
      return;
    }

    final noteText = _notesController.text.trim();
    final description =
        noteText.isNotEmpty ? noteText : '${_categoryLabel(_category)} expense';

    setState(() => _submitting = true);
    try {
      final api = ref.read(apiClientProvider);
      final reimbursement = await api.submitReimbursement(
        expenseDate: _today,
        amount: amount,
        category: _category,
        description: description,
        receiptUrl: _receipt?.name,
      );
      final reimbursementId = reimbursement['id']?.toString();
      if (reimbursementId != null && _receipt != null) {
        await api.uploadReimbursementReceipt(
          reimbursementId: reimbursementId,
          bytes: await _receipt!.readAsBytes(),
          filename: _receipt!.name,
        );
      }
      if (!mounted) return;
      _amountController.clear();
      _notesController.clear();
      setState(() => _receipt = null);
      _showSnack('Reimbursement submitted for approval.');
      await _load();
    } catch (e) {
      if (mounted) _showSnack('Failed to record expense: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _pickReceipt() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 80);
    if (picked != null && mounted) setState(() => _receipt = picked);
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
    final isDemo = session?.isDemo == true;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: PageScaffold(
        title: 'Expenses',
        subtitle:
            'Capture travel, food, lodging, and misc expenses on the go.',
        children: [
          if (isDemo) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Demo mode — login with your Katasticho ERP '
                        'credentials to record real expenses.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '1-TAP PHARMA TA / DA PRESETS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0B6B5E),
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ('FOOD', 'HQ Daily Allowance (₹250)', '250', 'HQ Daily Allowance — Standard Field Beat'),
                      ('TRAVEL', 'Ex-HQ DA + Fuel (₹450)', '450', 'Ex-HQ Outstation Beat + Bike Fuel'),
                      ('TRAVEL', 'Bike Petrol 50 KM (₹200)', '200', 'Bike Fuel Claim — 50 KM @ ₹4/km'),
                      ('FOOD', 'Outstation DA + Meals (₹600)', '600', 'Outstation Daily Allowance & Working Meals'),
                      ('LODGING', 'Hotel Lodging (₹1200)', '1200', 'Outstation Night Halt Hotel Bill'),
                    ].map((preset) {
                      return ActionChip(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: const Color(0xFFECFDF5),
                        side: const BorderSide(color: Color(0xFFA7F3D0)),
                        label: Text(
                          preset.$2,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF065F46),
                          ),
                        ),
                        onPressed: () {
                          setState(() {
                            _category = preset.$1;
                            _amountController.text = preset.$3;
                            _notesController.text = preset.$4;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'EXPENSE CATEGORY',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _categories.map((c) {
                      final selected = _category == c;
                      return ChoiceChip(
                        selected: selected,
                        selectedColor: const Color(0xFF0B6B5E),
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _categoryIcon(c),
                              size: 15,
                              color: selected ? Colors.white : const Color(0xFF475569),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _categoryLabel(c),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: selected ? Colors.white : const Color(0xFF334155),
                              ),
                            ),
                          ],
                        ),
                        onSelected: (_) => setState(() => _category = c),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Amount (₹) *',
                      prefixText: '₹ ',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notesController,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Expense Description / Route Remarks',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickReceipt,
                        icon: const Icon(Icons.photo_camera, size: 18),
                        label: Text(_receipt == null ? 'Attach Bill Photo' : 'Bill Attached ✓'),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: (isDemo || _submitting) ? null : _submit,
                          icon: _submitting
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.check_circle_outline, size: 18),
                          label: Text(
                            _submitting ? 'Submitting…' : 'Submit Claim',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "Today's Expenses",
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          if (_expenses.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.receipt_long, color: Colors.grey.shade400),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('No expenses recorded today.'),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._expenses.whereType<Map<String, dynamic>>().map(_expenseCard),
        ],
      ),
    );
  }

  Widget _expenseCard(Map<String, dynamic> expense) {
    final theme = Theme.of(context);
    final category = expense['category']?.toString() ?? 'MISC';
    final description = expense['description']?.toString() ?? '';
    final expenseDate = expense['expenseDate']?.toString() ?? '';
    final status = expense['status']?.toString() ?? 'SUBMITTED';
    final accountName = expense['accountName']?.toString() ?? '';
    final amount =
        (expense['total'] as num?)?.toDouble() ??
        (expense['amount'] as num?)?.toDouble() ??
        0;
    final color = _categoryColor(category);

    Color statusColor = Colors.orange;
    if (status == 'APPROVED') statusColor = const Color(0xFF2563EB);
    if (status == 'PAID') statusColor = const Color(0xFF059669);
    if (status == 'REJECTED') statusColor = Colors.red;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.14),
              foregroundColor: color,
              child: Icon(_categoryIcon(category)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    description.isNotEmpty
                        ? description
                        : _categoryLabel(category),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (expenseDate.isNotEmpty)
                        Text(
                          expenseDate,
                          style: theme.textTheme.bodySmall,
                        ),
                      if (accountName.isNotEmpty) ...[
                        const Text(' · ', style: TextStyle(color: Colors.grey)),
                        Expanded(
                          child: Text(
                            accountName,
                            style: theme.textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatCurrency(amount),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _categoryLabel(String category) {
    return switch (category) {
      'TRAVEL' => 'Travel',
      'FOOD' => 'Food',
      'LODGING' => 'Lodging',
      _ => 'Misc',
    };
  }

  IconData _categoryIcon(String category) {
    return switch (category) {
      'TRAVEL' => Icons.directions_car,
      'FOOD' => Icons.restaurant,
      'LODGING' => Icons.hotel,
      _ => Icons.receipt_long,
    };
  }

  Color _categoryColor(String category) {
    return switch (category) {
      'TRAVEL' => const Color(0xFF2563EB),
      'FOOD' => const Color(0xFFF59E0B),
      'LODGING' => const Color(0xFF7C3AED),
      _ => const Color(0xFF475569),
    };
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
