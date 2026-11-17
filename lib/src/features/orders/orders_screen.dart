import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/session.dart';
import '../auth/auth_controller.dart';
import 'order_builder_screen.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  List<Map<String, dynamic>> _visits = [];
  List<Map<String, dynamic>> _pobs = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
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
      final isPharma = session.isPharma;

      List<Map<String, dynamic>> visits = [];
      try {
        final executions = await api.getMyTodayExecutions();
        if (executions.isNotEmpty) {
          final exec = executions[0] as Map<String, dynamic>;
          final execId = exec['id']?.toString();
          if (execId != null) {
            final raw = await api.getVisits(execId);
            visits = raw
                .whereType<Map<String, dynamic>>()
                .where(
                  (v) =>
                      v['status'] == 'IN_PROGRESS' ||
                      v['status'] == 'COMPLETED',
                )
                .toList();
          }
        }
      } catch (e) {
        // visits load failed
        _error = e.toString();
      }

      List<Map<String, dynamic>> pobs = [];
      if (isPharma) {
        try {
          final rawPobs = await api.getPharmaPobs();
          pobs = rawPobs.whereType<Map<String, dynamic>>().toList();
        } catch (_) {
          // Gracefully ignore if not entitled or 403
        }
      }

      if (mounted) {
        setState(() {
          _visits = visits;
          _pobs = pobs;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showDirectOrderPicker() async {
    final api = ref.read(apiClientProvider);
    List<Map<String, dynamic>> contacts = [];
    try {
      final raw = await api.getContacts();
      contacts = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {}

    if (!mounted) return;

    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SelectPartySheet(contacts: contacts),
    );

    if (picked != null && mounted) {
      final placed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => OrderBuilderScreen(
            visitId: '',
            contactId: picked['id']?.toString() ?? '',
            contactName: picked['displayName']?.toString() ?? 'Party',
            medicalCategory: picked['medicalCategory']?.toString(),
          ),
        ),
      );
      if (placed == true && mounted) {
        await _loadAll();
      }
    }
  }

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
              title: const Text('Build order (items / POB)'),
              subtitle: const Text(
                'Browse catalog, select supplying stockist, build order',
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
            medicalCategory: visit['medicalCategory']?.toString(),
          ),
        ),
      );
      if (placed == true && mounted) await _loadAll();
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
            child: const Text('Record'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    try {
      await ref.read(apiClientProvider).recordOrder(
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
      await _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _shareStockistAdvice(String stockistId) async {
    try {
      final api = ref.read(apiClientProvider);
      final advice = await api.getStockistSupplyAdvice(stockistId);
      final shareText = advice['shareableWhatsAppText']?.toString() ?? '';

      if (shareText.isNotEmpty) {
        final encoded = Uri.encodeComponent(shareText);
        final uri = Uri.parse('https://wa.me/?text=$encoded');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No advice text generated')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate stockist advice: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(authControllerProvider).session;
    final isPharma = session?.isPharma == true;

    // Non-Pharma FMCG/Distributor Salesman view (Single clean Orders view)
    if (!isPharma) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Orders'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadAll,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showDirectOrderPicker,
          backgroundColor: const Color(0xFF2563EB),
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text(
            'Take Order',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadAll,
                child: _buildVisitOrdersView(theme, session),
              ),
      );
    }

    // Pharma MR View (Tabbed view: Visit Orders & Pharma POBs)
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders & POBs'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.route, size: 20),
              text: 'Visit Orders (${_visits.length})',
            ),
            Tab(
              icon: const Icon(Icons.medication, size: 20),
              text: 'Pharma POBs (${_pobs.length})',
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showDirectOrderPicker,
        backgroundColor: const Color(0xFF059669),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Book Order / POB',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                RefreshIndicator(
                  onRefresh: _loadAll,
                  child: _buildVisitOrdersView(theme, session),
                ),
                RefreshIndicator(
                  onRefresh: _loadAll,
                  child: _buildPobsView(theme),
                ),
              ],
            ),
    );
  }

  Widget _buildVisitOrdersView(ThemeData theme, FieldSession? session) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
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
                    child: Text('Login with real credentials to record orders.'),
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
                      'No active route visits today. Tap "Take Order" or "Book Order / POB" to record an off-beat order directly.',
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
              margin: const EdgeInsets.only(bottom: 10),
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
                        Chip(
                          label: Text(
                            status.replaceAll('_', ' '),
                            style: const TextStyle(fontSize: 11),
                          ),
                          side: BorderSide.none,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    if (existingOrder != null && existingOrder > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Recorded Order: ₹${existingOrder.toStringAsFixed(0)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.green.shade800,
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
                            : 'Record Order / POB',
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildPobsView(ThemeData theme) {
    if (_pobs.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.medication_outlined, color: Colors.grey.shade400),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'No POB orders recorded yet. Book orders at chemist counters tagged to preferred stockists.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: _pobs.length,
      itemBuilder: (ctx, i) {
        final pob = _pobs[i];
        final orderNum = pob['orderNumber']?.toString() ?? 'POB';
        final chemistName = pob['chemistName']?.toString() ?? 'Chemist';
        final stockistName = pob['stockistName']?.toString() ?? 'Stockist';
        final stockistId = pob['stockistId']?.toString();
        final totalAmount = (pob['totalAmount'] as num?)?.toDouble() ?? 0.0;
        final status = pob['status']?.toString() ?? 'BOOKED';
        final date = pob['orderDate']?.toString() ?? '';

        Color statusColor = Colors.orange;
        if (status == 'SUPPLIED') statusColor = Colors.green;
        if (status == 'BOOKED') statusColor = const Color(0xFF2563EB);

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      orderNum,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Chemist: $chemistName',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  'Supplying Stockist: $stockistName',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '₹${totalAmount.toStringAsFixed(0)}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF059669),
                      ),
                    ),
                    Text(date, style: theme.textTheme.bodySmall),
                  ],
                ),
                if (stockistId != null && stockistId.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF059669),
                        side: const BorderSide(color: Color(0xFF059669)),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => _shareStockistAdvice(stockistId),
                      icon: const Icon(Icons.share, size: 14),
                      label: const Text('WhatsApp Stockist Advice'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SelectPartySheet extends StatefulWidget {
  const _SelectPartySheet({required this.contacts});

  final List<Map<String, dynamic>> contacts;

  @override
  State<_SelectPartySheet> createState() => _SelectPartySheetState();
}

class _SelectPartySheetState extends State<_SelectPartySheet> {
  final _searchCtl = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.contacts.where((c) {
      if (_filter.isEmpty) return true;
      final name = c['displayName']?.toString().toLowerCase() ?? '';
      final phone = c['phone']?.toString().toLowerCase() ?? '';
      final city = c['billingCity']?.toString().toLowerCase() ?? '';
      final q = _filter.toLowerCase();
      return name.contains(q) || phone.contains(q) || city.contains(q);
    }).toList();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: Row(
              children: [
                const Icon(Icons.storefront, color: Color(0xFF059669)),
                const SizedBox(width: 10),
                const Text(
                  'Select Party for Order',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _searchCtl,
              onChanged: (v) => setState(() => _filter = v.trim()),
              decoration: InputDecoration(
                hintText: 'Search customer, retailer, or party name…',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.person_search,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _filter.isEmpty
                                ? 'No customers found in this tenant.'
                                : 'No party matching "$_filter"',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _filter.isEmpty
                                ? 'Add customers via Web Console or log in as Pharma MR (9000000029).'
                                : 'Try searching by name, city, or phone.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final c = filtered[i];
                      final name = c['displayName']?.toString() ?? 'Party';
                      final cat =
                          c['medicalCategory']?.toString().toUpperCase();
                      final city = c['billingCity']?.toString() ?? '';
                      final isChemist = cat == 'CHEMIST' || cat == 'RETAILER';

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isChemist
                              ? const Color(0xFF059669).withValues(alpha: 0.1)
                              : Colors.blue.withValues(alpha: 0.1),
                          child: Icon(
                            isChemist ? Icons.local_pharmacy : Icons.business,
                            color: isChemist
                                ? const Color(0xFF059669)
                                : Colors.blue,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text([
                          if (cat != null) cat,
                          if (city.isNotEmpty) city,
                        ].join(' · ')),
                        onTap: () => Navigator.pop(ctx, c),
                      );
                    },
                  ),
          ),
        ],
      ),
    ));
  }
}
