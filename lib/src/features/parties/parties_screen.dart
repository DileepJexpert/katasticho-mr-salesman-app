import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Demo mode shows sample data. Login with your '
                      'Katasticho ERP credentials to browse customers, '
                      'vendors, and their outstanding balances.',
                    ),
                  ),
                ],
              ),
            ),
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
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_contacts.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.people_outline, color: Colors.grey.shade400),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('No parties found.')),
                  ],
                ),
              ),
            )
          else
            ..._contacts.map(
              (raw) => _ContactCard(
                contact: raw as Map<String, dynamic>,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _ContactDetailScreen(
                        contactId: raw['id']?.toString() ?? '',
                        displayName: raw['displayName']?.toString() ?? 'Party',
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.contact, required this.onTap});

  final Map<String, dynamic> contact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
      if (phone.isNotEmpty) phone,
      if (city.isNotEmpty) city,
    ];

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.14),
                foregroundColor: color,
                child: Icon(_contactTypeIcon(type)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitleParts.isNotEmpty)
                      Text(
                        subtitleParts.join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                    const SizedBox(height: 2),
                    Text(
                      _contactTypeLabel(type),
                      style: theme.textTheme.bodySmall?.copyWith(color: color),
                    ),
                  ],
                ),
              ),
              if (outstanding > 0)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatCurrencyCompact(outstanding),
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text('due', style: theme.textTheme.bodySmall),
                  ],
                )
              else
                const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
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
    final theme = Theme.of(context);
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
                  Row(
                    children: [
                      Expanded(
                        child: MetricTile(
                          icon: Icons.call_received,
                          label: 'Receivable',
                          value: formatCurrencyCompact(receivable),
                          tint: receivable > 0
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF059669),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: MetricTile(
                          icon: Icons.call_made,
                          label: 'Payable',
                          value: formatCurrencyCompact(payable),
                          tint: const Color(0xFFF59E0B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: MetricTile(
                          icon: Icons.credit_score,
                          label: 'Credit limit',
                          value: creditLimit > 0
                              ? formatCurrencyCompact(creditLimit)
                              : '--',
                          tint: const Color(0xFF2563EB),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: MetricTile(
                          icon: Icons.schedule,
                          label: 'Payment terms',
                          value: termsDays > 0 ? '$termsDays days' : '--',
                          tint: const Color(0xFF7C3AED),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Details',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
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
                          ),
                        ],
                      ),
                    ),
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

  Widget _detailRow(IconData icon, String label, String? value) {
    final display = (value == null || value.isEmpty) ? '--' : value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
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
