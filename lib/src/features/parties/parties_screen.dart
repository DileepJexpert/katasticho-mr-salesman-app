import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/auth_controller.dart';
import '../mr/rcpa_sheet.dart';
import '../orders/order_builder_screen.dart';
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
  String _selectedCategory = 'ALL'; // ALL, DOCTOR, CHEMIST, STOCKIST, OTHER

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
    setState(() {}); // refresh clear button
  }

  List<dynamic> get _filteredContacts {
    if (_selectedCategory == 'ALL') return _contacts;
    return _contacts.where((raw) {
      final c = raw as Map<String, dynamic>;
      final cat = c['medicalCategory']?.toString().toUpperCase();
      if (_selectedCategory == 'DOCTOR') {
        return cat == 'DOCTOR';
      } else if (_selectedCategory == 'CHEMIST') {
        return cat == 'CHEMIST' || cat == 'RETAILER';
      } else if (_selectedCategory == 'STOCKIST') {
        return cat == 'STOCKIST' || cat == 'DISTRIBUTOR';
      } else {
        return cat == null || (cat != 'DOCTOR' && cat != 'CHEMIST' && cat != 'STOCKIST');
      }
    }).toList();
  }

  int _countFor(String catKey) {
    if (catKey == 'ALL') return _contacts.length;
    return _contacts.where((raw) {
      final c = raw as Map<String, dynamic>;
      final cat = c['medicalCategory']?.toString().toUpperCase();
      if (catKey == 'DOCTOR') return cat == 'DOCTOR';
      if (catKey == 'CHEMIST') return cat == 'CHEMIST' || cat == 'RETAILER';
      if (catKey == 'STOCKIST') return cat == 'STOCKIST' || cat == 'DISTRIBUTOR';
      return cat == null || (cat != 'DOCTOR' && cat != 'CHEMIST' && cat != 'STOCKIST');
    }).length;
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
                      'Katasticho ERP credentials to browse doctors, chemists, '
                      'stockists, and outstanding balances.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final filtered = _filteredContacts;

    return RefreshIndicator(
      onRefresh: _load,
      child: PageScaffold(
        title: 'Parties & Field Network',
        subtitle: 'Doctors, retail chemists, stockists, and institutional parties.',
        children: [
          // Search box
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              hintText: 'Search by name, phone, specialty, DL No, GSTIN…',
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
          const SizedBox(height: 10),

          // Pharma & Category Segment Filter Tabs
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('ALL', 'All', Icons.groups_outlined),
                const SizedBox(width: 6),
                _buildFilterChip('DOCTOR', 'Doctors', Icons.health_and_safety_outlined),
                const SizedBox(width: 6),
                _buildFilterChip('CHEMIST', 'Chemists', Icons.local_pharmacy_outlined),
                const SizedBox(width: 6),
                _buildFilterChip('STOCKIST', 'Stockists', Icons.warehouse_outlined),
                const SizedBox(width: 6),
                _buildFilterChip('OTHER', 'General', Icons.business_outlined),
              ],
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
          else if (filtered.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.people_outline, color: Colors.grey.shade400),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('No parties found matching criteria.')),
                  ],
                ),
              ),
            )
          else
            ...filtered.map(
              (raw) {
                final map = raw as Map<String, dynamic>;
                return _ContactCard(
                  contact: map,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _ContactDetailScreen(
                          contactId: map['id']?.toString() ?? '',
                          displayName: map['displayName']?.toString() ?? 'Party',
                        ),
                      ),
                    );
                  },
                  onBookPob: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => OrderBuilderScreen(
                          visitId: '',
                          contactId: map['id']?.toString() ?? '',
                          contactName: map['displayName']?.toString() ?? 'Party',
                          medicalCategory: map['medicalCategory']?.toString(),
                        ),
                      ),
                    );
                  },
                  onRcpa: () {
                    RcpaSheet.show(
                      context,
                      chemistId: map['id']?.toString(),
                      chemistName: map['displayName']?.toString(),
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label, IconData icon) {
    final isSelected = _selectedCategory == key;
    final count = _countFor(key);

    return FilterChip(
      selected: isSelected,
      label: Text('$label ($count)'),
      avatar: Icon(
        icon,
        size: 16,
        color: isSelected ? Colors.white : Colors.grey.shade700,
      ),
      selectedColor: const Color(0xFF2563EB),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.grey.shade800,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      onSelected: (_) {
        setState(() => _selectedCategory = key);
      },
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.contact,
    required this.onTap,
    this.onBookPob,
    this.onRcpa,
  });

  final Map<String, dynamic> contact;
  final VoidCallback onTap;
  final VoidCallback? onBookPob;
  final VoidCallback? onRcpa;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = contact['displayName']?.toString() ?? 'Unnamed';
    final medCat = contact['medicalCategory']?.toString().toUpperCase();
    final type = contact['contactType']?.toString() ?? 'CUSTOMER';
    final phone = contact['mobile']?.toString().isNotEmpty == true
        ? contact['mobile'].toString()
        : (contact['phone']?.toString() ?? '');
    final city = contact['billingCity']?.toString() ?? '';
    final district = contact['district']?.toString() ?? '';
    final specialty = contact['specialty']?.toString();
    final mrClass = contact['mrClass']?.toString();
    final dlNo = contact['drugLicenseNo1']?.toString();
    final outstanding = (contact['outstandingAr'] as num?)?.toDouble() ?? 0;

    final isDoctor = medCat == 'DOCTOR';
    final isChemist = medCat == 'CHEMIST' || medCat == 'RETAILER';
    final isStockist = medCat == 'STOCKIST' || medCat == 'DISTRIBUTOR';

    final Color primaryColor = isDoctor
        ? const Color(0xFF0D9488) // Teal
        : isChemist
            ? const Color(0xFF059669) // Emerald
            : isStockist
                ? const Color(0xFF4F46E5) // Indigo
                : _contactTypeColor(type);

    final IconData mainIcon = isDoctor
        ? Icons.health_and_safety
        : isChemist
            ? Icons.local_pharmacy
            : isStockist
                ? Icons.warehouse
                : _contactTypeIcon(type);

    final subtitleParts = <String>[
      if (phone.isNotEmpty) phone,
      if (district.isNotEmpty) district else if (city.isNotEmpty) city,
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: primaryColor.withValues(alpha: 0.12),
                    foregroundColor: primaryColor,
                    child: Icon(mainIcon),
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
                        const SizedBox(height: 4),

                        // Badges Row
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            // Category Badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: primaryColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isDoctor
                                    ? 'Doctor'
                                    : isChemist
                                        ? 'Chemist'
                                        : isStockist
                                            ? 'Stockist'
                                            : _contactTypeLabel(type),
                                style: TextStyle(
                                  color: primaryColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),

                            // Doctor Specialty Badge
                            if (isDoctor && specialty != null && specialty.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  specialty,
                                  style: TextStyle(
                                    color: Colors.blue.shade800,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),

                            // Doctor MR Priority Class Badge
                            if (isDoctor && mrClass != null && mrClass.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: mrClass == 'A'
                                      ? Colors.amber.shade100
                                      : mrClass == 'B'
                                          ? Colors.cyan.shade100
                                          : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Class $mrClass',
                                  style: TextStyle(
                                    color: mrClass == 'A'
                                        ? Colors.amber.shade900
                                        : mrClass == 'B'
                                            ? Colors.cyan.shade900
                                            : Colors.grey.shade800,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),

                            // Drug License Badge
                            if (dlNo != null && dlNo.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.purple.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'DL: $dlNo',
                                  style: TextStyle(
                                    color: Colors.purple.shade800,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Outstanding or Arrow
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

              // Action buttons for Chemist (Book POB & RCPA)
              if (isChemist) ...[
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: BorderSide(color: Colors.teal.shade400),
                      ),
                      onPressed: onRcpa,
                      icon: Icon(Icons.analytics_outlined, size: 14, color: Colors.teal.shade700),
                      label: Text(
                        'RCPA Audit',
                        style: TextStyle(fontSize: 12, color: Colors.teal.shade800, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: onBookPob,
                      icon: const Icon(Icons.shopping_bag_outlined, size: 14),
                      label: const Text(
                        'Book POB',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
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

  Future<void> _callPhone(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot make call to $cleanPhone')),
        );
      }
    }
  }

  Future<void> _viewStockistAdvice(String stockistId) async {
    try {
      final api = ref.read(apiClientProvider);
      final advice = await api.getStockistSupplyAdvice(stockistId);
      final shareText = advice['shareableWhatsAppText']?.toString() ?? '';
      final totalValue = (advice['totalValue'] as num?)?.toDouble() ?? 0.0;
      final totalOrders = advice['totalOrders'] ?? 0;

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Stockist Supply Advice ($totalOrders Orders)'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Consolidated Value: ${formatCurrencyCompact(totalValue)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: SelectableText(
                    shareText.isNotEmpty ? shareText : 'No pending chemist orders for this stockist.',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            if (shareText.isNotEmpty)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                icon: const Icon(Icons.share, size: 16),
                label: const Text('WhatsApp Stockist'),
                onPressed: () async {
                  final encoded = Uri.encodeComponent(shareText);
                  final uri = Uri.parse('https://wa.me/?text=$encoded');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load stockist advice: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = _contact['displayName']?.toString() ?? widget.displayName;
    final medCat = _contact['medicalCategory']?.toString().toUpperCase();
    final receivable = (_contact['outstandingAr'] as num?)?.toDouble() ?? 0;
    final payable = (_contact['outstandingAp'] as num?)?.toDouble() ?? 0;
    final creditLimit = (_contact['creditLimit'] as num?)?.toDouble() ?? 0;
    final termsDays = (_contact['paymentTermsDays'] as num?)?.toInt() ?? 0;

    final isDoctor = medCat == 'DOCTOR';
    final isChemist = medCat == 'CHEMIST' || medCat == 'RETAILER';
    final isStockist = medCat == 'STOCKIST' || medCat == 'DISTRIBUTOR';
    final phone = _contact['mobile']?.toString() ?? _contact['phone']?.toString();

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

                  // Metric Row
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

                  // Pharma Classification Section (If Doctor, Chemist, or Stockist)
                  if (isDoctor || isChemist || isStockist) ...[
                    Text(
                      'Pharma & Medical Profile',
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
                            if (isDoctor) ...[
                              _detailRow(Icons.health_and_safety, 'Specialty', _contact['specialty']?.toString()),
                              _detailRow(Icons.star, 'MR Priority Class', _contact['mrClass']?.toString() != null ? 'Class ${_contact['mrClass']}' : null),
                              _detailRow(Icons.calendar_month, 'Visits Per Month', _contact['visitsPerMonth']?.toString()),
                            ],
                            if (isChemist || isStockist) ...[
                              _detailRow(Icons.badge, 'Drug License No 1', _contact['drugLicenseNo1']?.toString()),
                              _detailRow(Icons.badge_outlined, 'Drug License No 2', _contact['drugLicenseNo2']?.toString()),
                              _detailRow(Icons.event_available, 'DL Expiry', _contact['drugLicenseExpiryDate']?.toString()),
                              _detailRow(Icons.restaurant, 'FSSAI Number', _contact['fssaiNumber']?.toString()),
                            ],
                            _detailRow(Icons.map, 'District', _contact['district']?.toString()),
                            _detailRow(Icons.place, 'Place of Supply', _contact['placeOfSupply']?.toString()),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // General Contact Details
                  Text(
                    'Contact & Address Details',
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
                            Icons.credit_card,
                            'PAN',
                            _contact['pan']?.toString(),
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
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              if (phone != null && phone.isNotEmpty) ...[
                OutlinedButton.icon(
                  onPressed: () => _callPhone(phone),
                  icon: const Icon(Icons.phone),
                  label: const Text('Call'),
                ),
                const SizedBox(width: 8),
              ],
              if (isChemist) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.teal.shade500)),
                    onPressed: () {
                      RcpaSheet.show(
                        context,
                        chemistId: widget.contactId,
                        chemistName: name,
                      );
                    },
                    icon: Icon(Icons.analytics_outlined, color: Colors.teal.shade800),
                    label: Text('RCPA', style: TextStyle(color: Colors.teal.shade900)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669)),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => OrderBuilderScreen(
                            visitId: '',
                            contactId: widget.contactId,
                            contactName: name,
                            medicalCategory: 'CHEMIST',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.shopping_bag_outlined),
                    label: const Text('Book POB'),
                  ),
                ),
              ] else if (isStockist) ...[
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF4F46E5)),
                    onPressed: () => _viewStockistAdvice(widget.contactId),
                    icon: const Icon(Icons.assignment_outlined),
                    label: const Text('Supply Advice'),
                  ),
                ),
              ] else ...[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => OrderBuilderScreen(
                            visitId: '',
                            contactId: widget.contactId,
                            contactName: name,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.shopping_cart_outlined),
                    label: const Text('New Order'),
                  ),
                ),
              ],
            ],
          ),
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
            width: 130,
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

/// ₹ compact formatting shared with dashboard style: ₹X.XL / ₹X.Xk.
String formatCurrencyCompact(double value) {
  if (value >= 100000) {
    return '₹${(value / 100000).toStringAsFixed(1)}L';
  } else if (value >= 1000) {
    return '₹${(value / 1000).toStringAsFixed(1)}k';
  }
  return '₹${value.toStringAsFixed(0)}';
}
