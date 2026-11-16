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
  List<dynamic> _accounts = [];

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
      final results = await Future.wait([
        api.getReimbursements(),
        api.getAccounts(),
      ]);
      if (mounted) {
        setState(() {
          _expenses = results[0];
          _accounts = results[1];
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Picks the expense (debit) account for the selected category by name
  /// keywords, falling back to a Miscellaneous / first EXPENSE account.
  Map<String, dynamic>? _resolveExpenseAccount(String category) {
    final keywords = switch (category) {
      'TRAVEL' => ['travel', 'conveyance', 'transport'],
      'FOOD' => ['food', 'meal', 'staff welfare', 'refreshment'],
      'LODGING' => ['lodging', 'hotel', 'accommodation', 'boarding'],
      _ => ['miscellaneous', 'misc', 'general', 'other'],
    };

    final expenseAccounts = _accounts
        .whereType<Map<String, dynamic>>()
        .where((a) => a['type']?.toString() == 'EXPENSE')
        .toList();

    for (final keyword in keywords) {
      for (final account in expenseAccounts) {
        final name = account['name']?.toString().toLowerCase() ?? '';
        if (name.contains(keyword)) return account;
      }
    }
    // Fallback: a Miscellaneous expense account, then any expense account.
    for (final account in expenseAccounts) {
      final name = account['name']?.toString().toLowerCase() ?? '';
      if (name.contains('miscellaneous') || name.contains('misc')) {
        return account;
      }
    }
    return expenseAccounts.isNotEmpty ? expenseAccounts.first : null;
  }


  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      _showSnack('Enter a valid amount.');
      return;
    }

    final expenseAccount = _resolveExpenseAccount(_category);
    final accountId = expenseAccount?['id']?.toString();
    final noteText = _notesController.text.trim();
    final description =
        noteText.isNotEmpty ? noteText : '${_categoryLabel(_category)} expense';

    setState(() => _submitting = true);
    try {
      final api = ref.read(apiClientProvider);
      final reimbursement = await api.submitReimbursement(
        expenseDate: _today,
        accountId: accountId,
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
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(
                      labelText: 'Expense type',
                    ),
                    items: _categories
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(_categoryLabel(c)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _category = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Amount',
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
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _pickReceipt,
                      icon: const Icon(Icons.photo_camera),
                      label: Text(_receipt == null ? 'Attach receipt photo' : 'Receipt attached'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: (isDemo || _submitting) ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(
                        _submitting ? 'Recording…' : 'Record expense',
                      ),
                    ),
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
