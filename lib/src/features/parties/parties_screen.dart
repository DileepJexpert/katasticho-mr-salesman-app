import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../auth/auth_controller.dart';
import '../shared/field_widgets.dart';

class PartiesScreen extends ConsumerStatefulWidget {
  const PartiesScreen({super.key});

  @override
  ConsumerState<PartiesScreen> createState() => _PartiesScreenState();
}

class _PartiesScreenState extends ConsumerState<PartiesScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  bool _loading = true;
  String? _error;
  List<dynamic> _contacts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

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
      final contacts = await api.getContacts(
        search: _searchController.text.trim(),
      );
      if (mounted) setState(() => _contacts = contacts);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _load);
    setState(() {}); // refresh the clear button visibility
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).session;
    final theme = Theme.of(context);

    if (session?.isDemo == true) {
      return PageScaffold(
        title: 'Parties',
        subtitle: 'Demo mode — login with real credentials to see live data.',
        children: [
          StatusStrip(
            icon: Icons.info_outline,
            color: theme.colorScheme.primary,
            text:
                'Demo mode shows sample data. Login with your Katasticho ERP '
                'credentials to browse customers, vendors, and balances.',
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: PageScaffold(
        title: 'Parties',
        subtitle: 'Customers and vendors from your organisation.',
        children: [
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              hintText: 'Search by name, phone, GSTIN…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _debounce?.cancel();
                        _load();
                      },
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null) ...[
            StatusStrip(
              icon: Icons.error_outline,
              color: const Color(0xFFDC2626),
              text: _error!,
            ),
            const SizedBox(height: 12),
          ],
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_contacts.isEmpty)
            const FieldRow(
              leading: Icon(Icons.people_outline, color: FieldUi.muted),
              title: 'No parties found.',
              divider: false,
            )
          else ...[
            MetricStrip(items: _summaryItems()),
            const SizedBox(height: 12),
            SectionLabel('${_contacts.length} parties'),
            FlatList(
              children: [
                for (var i = 0; i < _contacts.length; i++)
                  _contactRow(
                    context,
                    _contacts[i] as Map<String, dynamic>,
                    last: i == _contacts.length - 1,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Single financial summary band across all loaded parties.
  List<MetricItem> _summaryItems() {
    double receivable = 0;
    double payable = 0;
    var withDues = 0;
    for (final raw in _contacts) {
      final c = raw as Map<String, dynamic>;
      final ar = (c['outstandingAr'] as num?)?.toDouble() ?? 0;
      final ap = (c['outstandingAp'] as num?)?.toDouble() ?? 0;
      receivable += ar;
      payable += ap;
      if (ar > 0) withDues++;
    }
    return [
      MetricItem(
        'Receivable',
        formatCurrencyCompact(receivable),
        color: receivable > 0 ? const Color(0xFFDC2626) : FieldUi.ink,
      ),
      MetricItem(
        'Payable',
        formatCurrencyCompact(payable),
        color: const Color(0xFFF59E0B),
      ),
      MetricItem('With dues', '$withDues'),
    ];
  }

  Widget _contactRow(
    BuildContext context,
    Map<String, dynamic> contact, {
    required bool last,
  }) {
    final theme = Theme.of(context);
    final name = contact['displayName']?.toString() ?? 'Unnamed';
    final type = contact['contactType']?.toString() ?? 'CUSTOMER';
    final phone = contact['mobile']?.toString().isNotEmpty == true
        ? contact['mobile'].toString()
        : (contact['phone']?.toString() ?? '');
    final city = contact['billingCity']?.toString() ?? '';
    final outstanding = (contact['outstandingAr'] as num?)?.toDouble() ?? 0;
    final color = _contactTypeColor(type);

    final subtitleParts = <String>[
      _contactTypeLabel(type),
      if (phone.isNotEmpty) phone,
      if (city.isNotEmpty) city,
    ];

    final Widget trailing = outstanding > 0
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatCurrencyCompact(outstanding),
                style: const TextStyle(
                  color: Color(0xFFDC2626),
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'due',
                style: theme.textTheme.bodySmall?.copyWith(color: FieldUi.muted),
              ),
            ],
          )
        : const Icon(Icons.chevron_right, color: FieldUi.muted);

    return FieldRow(
      divider: !last,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: color.withValues(alpha: 0.14),
        foregroundColor: color,
        child: Icon(_contactTypeIcon(type), size: 18),
      ),
      title: name,
      subtitle: subtitleParts.join(' · '),
      trailing: trailing,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _ContactDetailScreen(
              contactId: contact['id']?.toString() ?? '',
              displayName: contact['displayName']?.toString() ?? 'Party',
            ),
          ),
        );
      },
    );
  }
}

class _ContactDetailScreen extends ConsumerStatefulWidget {
  const _ContactDetailScreen({
    required this.contactId,
    required this.displayName,
  });

  final String contactId;
  final String displayName;

  @override
  ConsumerState<_ContactDetailScreen> createState() =>
      _ContactDetailScreenState();
}

class _ContactDetailScreenState extends ConsumerState<_ContactDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _contact = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final contact = await api.getContact(widget.contactId);
      if (mounted) setState(() => _contact = contact);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _contact['displayName']?.toString() ?? widget.displayName;
    final receivable = (_contact['outstandingAr'] as num?)?.toDouble() ?? 0;
    final payable = (_contact['outstandingAp'] as num?)?.toDouble() ?? 0;
    final creditLimit = (_contact['creditLimit'] as num?)?.toDouble() ?? 0;
    final termsDays = (_contact['paymentTermsDays'] as num?)?.toInt() ?? 0;

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) ...[
                    StatusStrip(
                      icon: Icons.error_outline,
                      color: const Color(0xFFDC2626),
                      text: _error!,
                    ),
                    const SizedBox(height: 12),
                  ],
                  MetricStrip(
                    items: [
                      MetricItem(
                        'Receivable',
                        formatCurrencyCompact(receivable),
                        color: receivable > 0
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF059669),
                      ),
                      MetricItem(
                        'Payable',
                        formatCurrencyCompact(payable),
                        color: const Color(0xFFF59E0B),
                      ),
                      MetricItem(
                        'Credit limit',
                        creditLimit > 0
                            ? formatCurrencyCompact(creditLimit)
                            : '--',
                      ),
                      MetricItem(
                        'Terms',
                        termsDays > 0 ? '$termsDays d' : '--',
                      ),
                    ],
                  ),
                  const SectionLabel('Details'),
                  FlatList(
                    children: [
                      _detailRow(
                        Icons.phone,
                        'Phone',
                        _contact['phone']?.toString(),
                      ),
                      _detailRow(
                        Icons.smartphone,
                        'Mobile',
                        _contact['mobile']?.toString(),
                      ),
                      _detailRow(
                        Icons.email,
                        'Email',
                        _contact['email']?.toString(),
                      ),
                      _detailRow(
                        Icons.receipt_long,
                        'GSTIN',
                        _contact['gstin']?.toString(),
                      ),
                      _detailRow(
                        Icons.location_on,
                        'Billing address',
                        _billingAddress(),
                        last: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  String? _billingAddress() {
    final parts = <String>[
      _contact['billingAddressLine1']?.toString() ?? '',
      _contact['billingAddressLine2']?.toString() ?? '',
      _contact['billingCity']?.toString() ?? '',
      _contact['billingState']?.toString() ?? '',
      _contact['billingPostalCode']?.toString() ?? '',
    ].where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  Widget _detailRow(
    IconData icon,
    String label,
    String? value, {
    bool last = false,
  }) {
    final display = (value == null || value.isEmpty) ? '--' : value;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: FieldUi.muted),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: FieldUi.muted),
            ),
          ),
          Expanded(
            child: Text(
              display,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    if (last) return row;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [row, const Divider(height: 1)],
    );
  }
}

String _contactTypeLabel(String type) {
  return switch (type) {
    'CUSTOMER' => 'Customer',
    'VENDOR' => 'Vendor',
    'BOTH' => 'Customer & Vendor',
    _ => type,
  };
}

IconData _contactTypeIcon(String type) {
  return switch (type) {
    'CUSTOMER' => Icons.storefront,
    'VENDOR' => Icons.local_shipping,
    'BOTH' => Icons.swap_horiz,
    _ => Icons.person,
  };
}

Color _contactTypeColor(String type) {
  return switch (type) {
    'CUSTOMER' => const Color(0xFF059669),
    'VENDOR' => const Color(0xFF0891B2),
    'BOTH' => const Color(0xFF7C3AED),
    _ => const Color(0xFF475569),
  };
}

/// ₹ compact formatting shared with the dashboard style: ₹X.XL / ₹X.Xk.
String formatCurrencyCompact(double value) {
  if (value >= 100000) {
    return '₹${(value / 100000).toStringAsFixed(1)}L';
  } else if (value >= 1000) {
    return '₹${(value / 1000).toStringAsFixed(1)}k';
  }
  return '₹${value.toStringAsFixed(0)}';
}
