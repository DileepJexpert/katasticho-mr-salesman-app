import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import 'rcpa_sheet.dart';

/// RCPA (Retail Chemist Prescription Audit) Market Intelligence Screen.
/// Lists prescription intelligence gathered across chemists and doctors:
/// our brands vs competitor brands, pricing, and monthly prescription volumes.
class RcpaScreen extends ConsumerStatefulWidget {
  const RcpaScreen({super.key});

  @override
  ConsumerState<RcpaScreen> createState() => _RcpaScreenState();
}

class _RcpaScreenState extends ConsumerState<RcpaScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _audits = [];
  final _searchCtl = TextEditingController();
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
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
      final raw = await api.getEnrichedRcpaAudits();
      if (mounted) {
        setState(() {
          _audits = raw.whereType<Map<String, dynamic>>().toList();
        });
      }
    } catch (e) {
      // Fallback to basic audits if enriched is unavailable
      try {
        final api = ref.read(apiClientProvider);
        final basic = await api.getMyRcpaAudits();
        if (mounted) {
          setState(() {
            _audits = basic.whereType<Map<String, dynamic>>().toList();
          });
        }
      } catch (err) {
        if (mounted) setState(() => _error = err.toString());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredAudits {
    if (_filter.isEmpty) return _audits;
    final q = _filter.toLowerCase();
    return _audits.where((a) {
      final chemist = a['chemistName']?.toString().toLowerCase() ?? '';
      final doctor = a['doctorName']?.toString().toLowerCase() ?? '';
      final prod = a['productName']?.toString().toLowerCase() ?? '';
      final comp = a['competitorName']?.toString().toLowerCase() ?? '';
      final molecule = a['moleculeName']?.toString().toLowerCase() ?? '';
      return chemist.contains(q) ||
          doctor.contains(q) ||
          prod.contains(q) ||
          comp.contains(q) ||
          molecule.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredAudits;

    // Aggregate metrics
    final totalAudits = _audits.length;
    final distinctChemists = _audits.map((a) => a['chemistContactId']).toSet().length;
    final distinctDoctors = _audits
        .map((a) => a['doctorContactId'])
        .where((id) => id != null)
        .toSet()
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prescription Audits (RCPA)'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.teal.shade700,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'New RCPA Audit',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        onPressed: () async {
          final added = await RcpaSheet.show(context);
          if (added == true && mounted) {
            await _loadData();
          }
        },
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                children: [
                  // KPI Cards Header
                  Row(
                    children: [
                      Expanded(
                        child: _MetricCard(
                          icon: Icons.analytics_outlined,
                          label: 'Total Audits',
                          value: '$totalAudits',
                          color: Colors.teal,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MetricCard(
                          icon: Icons.local_pharmacy_outlined,
                          label: 'Chemists',
                          value: '$distinctChemists',
                          color: const Color(0xFF059669),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MetricCard(
                          icon: Icons.health_and_safety_outlined,
                          label: 'Doctors',
                          value: '$distinctDoctors',
                          color: const Color(0xFF2563EB),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Search Filter
                  TextField(
                    controller: _searchCtl,
                    onChanged: (v) => setState(() => _filter = v.trim()),
                    decoration: InputDecoration(
                      hintText: 'Search brand, chemist, doctor, molecule…',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _filter.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchCtl.clear();
                                setState(() => _filter = '');
                              },
                            )
                          : null,
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

                  if (filtered.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Icon(Icons.analytics_outlined, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 10),
                            const Text(
                              'No prescription audits found.',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tap "+ New RCPA Audit" to capture competitor prescription share.',
                              style: theme.textTheme.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ...filtered.map((audit) => _buildAuditCard(audit, theme)),
                ],
              ),
            ),
    );
  }

  Widget _buildAuditCard(Map<String, dynamic> audit, ThemeData theme) {
    final chemist = audit['chemistName']?.toString() ?? 'Chemist';
    final doctor = audit['doctorName']?.toString();
    final doctorSpec = audit['doctorSpecialty']?.toString();
    final ourProd = audit['ourProductName']?.toString() ?? audit['productName']?.toString() ?? 'Our Product';
    final compBrand = audit['competitorName']?.toString() ?? audit['productName']?.toString() ?? 'Competitor';
    final molecule = audit['moleculeName']?.toString();
    final date = audit['auditDate']?.toString() ?? '';
    final remarks = audit['remarks']?.toString();

    final lines = (audit['lines'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? [];
    final firstLine = lines.isNotEmpty ? lines.first : audit;
    final qty = (firstLine['quantity'] as num?)?.toDouble() ?? 0.0;
    final price = (firstLine['value'] as num?)?.toDouble() ?? 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Chemist & Date Header
            Row(
              children: [
                const Icon(Icons.local_pharmacy, size: 18, color: Color(0xFF059669)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    chemist,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(date, style: theme.textTheme.bodySmall),
              ],
            ),

            // Prescribing Doctor (if any)
            if (doctor != null && doctor.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.person_pin, size: 16, color: Color(0xFF2563EB)),
                  const SizedBox(width: 6),
                  Text(
                    'Dr. $doctor ${doctorSpec != null ? '($doctorSpec)' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 10),

            // Comparison Container
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Moonford Brand
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'MOONFORD BRAND',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal.shade700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              ourProd,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'VS',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                      // Competitor Brand
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'COMPETITOR',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              compBrand,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (price > 0)
                        Text(
                          'Comp. Price: ₹${price.toStringAsFixed(0)}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      if (qty > 0)
                        Text(
                          'Monthly Vol: ${qty.toStringAsFixed(0)} units',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.purple.shade800,
                          ),
                        ),
                    ],
                  ),
                  if (molecule != null && molecule.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Molecule: $molecule',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            if (remarks != null && remarks.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Notes: $remarks',
                style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}


