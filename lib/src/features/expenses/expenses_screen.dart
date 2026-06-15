import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
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
        api.getExpenses(from: _today, to: _today),
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

  /// Cash account (1010) used as the paid-through account for CASH spend.
  Map<String, dynamic>? _resolveCashAccount() {
    final accounts = _accounts.whereType<Map<String, dynamic>>().toList();
    for (final account in accounts) {
      if (account['code']?.toString() == '1010') return account;
    }
    for (final account in accounts) {
      final name = account['name']?.toString().toLowerCase() ?? '';
      if (account['type']?.toString() == 'ASSET' && name.contains('cash')) {
        return account;
      }
    }
    return null;
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      _showSnack('Enter a valid amount.');
      return;
    }

    final expenseAccount = _resolveExpenseAccount(_category);
    final cashAccount = _resolveCashAccount();
    if (expenseAccount == null || cashAccount == null) {
      _showSnack(
        'Could not resolve expense/cash accounts. '
        'Ask your admin to set up the chart of accounts.',
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.createExpense(
        expenseDate: _today,
        accountId: expenseAccount['id'].toString(),
        amount: amount,
        paymentMode: 'CASH',
        paidThroughId: cashAccount['id'].toString(),
        category: _category,
        description: _notesController.text.trim(),
      );
      if (!mounted) return;
      _amountController.clear();
      _notesController.clear();
      Navigator.of(context).maybePop();
      _showSnack('Expense recorded.');
      await _load();
    } catch (e) {
      if (mounted) _showSnack('Failed to record expense: $e');
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

  double _expenseTotal() {
    var total = 0.0;
    for (final expense in _expenses.whereType<Map<String, dynamic>>()) {
      total +=
          (expense['total'] as num?)?.toDouble() ??
          (expense['amount'] as num?)?.toDouble() ??
          0;
    }
    return total;
  }

  void _openForm() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final viewInsets = MediaQuery.of(sheetContext).viewInsets.bottom;
        // Local setState for the sheet so the dropdown / submit spinner update.
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + viewInsets),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: FieldUi.hairline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SectionLabel('Record expense'),
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(labelText: 'Expense type'),
                    items: _categories
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(_categoryLabel(c)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setSheetState(() => _category = value);
                      }
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
                      onPressed: () =>
                          _showSnack('Receipt photo capture coming soon.'),
                      icon: const Icon(Icons.photo_camera),
                      label: const Text('Attach receipt photo'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _submitting
                        ? null
                        : () async {
                            await _submit();
                            setSheetState(() {});
                          },
                    icon: _submitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(_submitting ? 'Recording…' : 'Record expense'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).session;
    final theme = Theme.of(context);
    final isDemo = session?.isDemo == true;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final expenses = _expenses.whereType<Map<String, dynamic>>().toList();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: PageScaffold(
          title: 'Expenses',
          subtitle:
              'Capture travel, food, lodging, and misc expenses on the go.',
          children: [
            if (isDemo) ...[
              StatusStrip(
                icon: Icons.info_outline,
                text:
                    'Demo mode — login with your Katasticho ERP credentials to '
                    'record real expenses.',
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 12),
            ],
            if (_error != null) ...[
              StatusStrip(
                icon: Icons.error_outline,
                text: _error!,
                color: Colors.red.shade700,
              ),
              const SizedBox(height: 12),
            ],
            if (expenses.isNotEmpty) ...[
              MetricStrip(
                items: [
                  MetricItem('Entries', '${expenses.length}'),
                  MetricItem('Total', _formatCurrency(_expenseTotal())),
                ],
              ),
            ],
            const SectionLabel("Today's expenses"),
            if (expenses.isEmpty)
              FlatList(
                children: [
                  FieldRow(
                    leading: Icon(
                      Icons.receipt_long,
                      color: Colors.grey.shade400,
                    ),
                    title: 'No expenses recorded today.',
                    subtitle: 'Tap + to add your first expense.',
                    divider: false,
                  ),
                ],
              )
            else
              FlatList(
                children: [
                  for (var i = 0; i < expenses.length; i++)
                    _expenseRow(expenses[i], last: i == expenses.length - 1),
                ],
              ),
          ],
        ),
      ),
      floatingActionButton: isDemo
          ? null
          : FloatingActionButton.extended(
              onPressed: _openForm,
              icon: const Icon(Icons.add),
              label: const Text('Add expense'),
            ),
    );
  }

  Widget _expenseRow(Map<String, dynamic> expense, {required bool last}) {
    final category = expense['category']?.toString() ?? 'MISC';
    final description = expense['description']?.toString() ?? '';
    final number = expense['expenseNumber']?.toString() ?? '';
    final status = expense['status']?.toString() ?? '';
    final amount =
        (expense['total'] as num?)?.toDouble() ??
        (expense['amount'] as num?)?.toDouble() ??
        0;
    final color = _categoryColor(category);

    final subtitle = [
      if (number.isNotEmpty) number,
      if (status.isNotEmpty) status,
    ].join(' · ');

    return FieldRow(
      divider: !last,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: color.withValues(alpha: 0.14),
        foregroundColor: color,
        child: Icon(_categoryIcon(category), size: 18),
      ),
      title: description.isNotEmpty ? description : _categoryLabel(category),
      subtitle: subtitle.isEmpty ? null : subtitle,
      trailing: Text(
        _formatCurrency(amount),
        style: const TextStyle(fontWeight: FontWeight.w800),
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
