import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';

/// Bottom sheet / dialog to record a Retail Chemist Prescription Audit (RCPA).
/// Captures doctor prescription intelligence at a chemist counter:
/// our brand vs competitor brand, price difference, and monthly Rx volume.
class RcpaSheet extends ConsumerStatefulWidget {
  const RcpaSheet({
    super.key,
    this.chemistId,
    this.chemistName,
    this.fieldVisitId,
  });

  final String? chemistId;
  final String? chemistName;
  final String? fieldVisitId;

  static Future<bool?> show(
    BuildContext context, {
    String? chemistId,
    String? chemistName,
    String? fieldVisitId,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: RcpaSheet(
          chemistId: chemistId,
          chemistName: chemistName,
          fieldVisitId: fieldVisitId,
        ),
      ),
    );
  }

  @override
  ConsumerState<RcpaSheet> createState() => _RcpaSheetState();
}

class _RcpaSheetState extends ConsumerState<RcpaSheet> {
  final _formKey = GlobalKey<FormState>();

  String? _selectedChemistId;
  String? _selectedChemistName;
  String? _selectedDoctorId;

  List<Map<String, dynamic>> _chemists = [];
  List<Map<String, dynamic>> _doctors = [];
  List<Map<String, dynamic>> _catalogItems = [];
  bool _loadingLookups = true;

  // Audit Line Fields
  Map<String, dynamic>? _selectedOurItem;
  final _competitorBrandCtl = TextEditingController();
  final _moleculeCtl = TextEditingController();
  final _competitorPriceCtl = TextEditingController();
  final _monthlyQtyCtl = TextEditingController();
  final _remarksCtl = TextEditingController();

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selectedChemistId = widget.chemistId;
    _selectedChemistName = widget.chemistName;
    _loadLookups();
  }

  @override
  void dispose() {
    _competitorBrandCtl.dispose();
    _moleculeCtl.dispose();
    _competitorPriceCtl.dispose();
    _monthlyQtyCtl.dispose();
    _remarksCtl.dispose();
    super.dispose();
  }

  Future<void> _loadLookups() async {
    setState(() => _loadingLookups = true);
    try {
      final api = ref.read(apiClientProvider);
      final results = await Future.wait([
        api.getContacts(),
        api.searchItems(''),
      ]);

      final allContacts = results[0].whereType<Map<String, dynamic>>().toList();
      final items = results[1].whereType<Map<String, dynamic>>().toList();

      final chemists = allContacts.where((c) {
        final cat = c['medicalCategory']?.toString().toUpperCase();
        return cat == 'CHEMIST' || cat == 'RETAILER' || c['contactType'] == 'CUSTOMER';
      }).toList();

      final doctors = allContacts.where((c) {
        final cat = c['medicalCategory']?.toString().toUpperCase();
        return cat == 'DOCTOR' || c['specialty'] != null;
      }).toList();

      if (mounted) {
        setState(() {
          _chemists = chemists;
          _doctors = doctors;
          _catalogItems = items;
          _loadingLookups = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingLookups = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final chemistId = _selectedChemistId;
    if (chemistId == null || chemistId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a chemist')),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final api = ref.read(apiClientProvider);
      final todayStr = DateTime.now().toIso8601String().split('T')[0];

      final ourItemName = _selectedOurItem?['name']?.toString() ?? '';
      final ourItemId = _selectedOurItem?['id']?.toString();
      final compBrand = _competitorBrandCtl.text.trim();
      final molecule = _moleculeCtl.text.trim();
      final price = double.tryParse(_competitorPriceCtl.text.trim()) ?? 0.0;
      final qty = double.tryParse(_monthlyQtyCtl.text.trim()) ?? 0.0;

      final lines = <Map<String, dynamic>>[
        {
          'productName': compBrand.isNotEmpty ? compBrand : ourItemName,
          'brandType': 'COMPETITOR',
          'competitorName': compBrand,
          if (ourItemId != null && ourItemId.isNotEmpty) 'ourItemId': ourItemId,
          'quantity': qty,
          'value': price,
          if (_selectedDoctorId != null && _selectedDoctorId!.isNotEmpty)
            'doctorContactId': _selectedDoctorId,
          if (molecule.isNotEmpty) 'moleculeName': molecule,
        },
      ];

      await api.recordRcpa(
        chemistContactId: chemistId,
        doctorContactId: _selectedDoctorId,
        auditDate: todayStr,
        fieldVisitId: widget.fieldVisitId,
        remarks: _remarksCtl.text.trim().isNotEmpty ? _remarksCtl.text.trim() : null,
        lines: lines,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('RCPA Audit recorded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to record RCPA: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.analytics_outlined, color: Colors.teal),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Prescription Audit (RCPA)',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        _selectedChemistName != null
                            ? 'Chemist: $_selectedChemistName'
                            : 'Competitor Brand & Doctor Intelligence',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),

          // Body Form
          Expanded(
            child: _loadingLookups
                ? const Center(child: CircularProgressIndicator())
                : Form(
                    key: _formKey,
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        // Chemist Selector (if not prefilled)
                        if (widget.chemistId == null) ...[
                          DropdownButtonFormField<String>(
                            initialValue: _selectedChemistId,
                            decoration: InputDecoration(
                              labelText: 'Chemist / Retailer *',
                              prefixIcon: const Icon(Icons.local_pharmacy_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            items: _chemists.map((c) {
                              final id = c['id']?.toString() ?? '';
                              final name = c['displayName']?.toString() ?? 'Chemist';
                              return DropdownMenuItem(value: id, child: Text(name));
                            }).toList(),
                            onChanged: (val) {
                              setState(() {
                                _selectedChemistId = val;
                                final match = _chemists.firstWhere(
                                  (c) => c['id']?.toString() == val,
                                  orElse: () => {},
                                );
                                _selectedChemistName = match['displayName']?.toString();
                              });
                            },
                            validator: (v) => v == null ? 'Chemist is required' : null,
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Prescribing Doctor
                        DropdownButtonFormField<String>(
                          initialValue: _selectedDoctorId,
                          decoration: InputDecoration(
                            labelText: 'Prescribing Doctor',
                            prefixIcon: const Icon(Icons.person_pin_outlined),
                            hintText: 'Select doctor who prescribed',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('General / Counter Sale')),
                            ..._doctors.map((d) {
                              final id = d['id']?.toString() ?? '';
                              final name = d['displayName']?.toString() ?? 'Doctor';
                              final spec = d['specialty']?.toString();
                              final label = spec != null ? '$name ($spec)' : name;
                              return DropdownMenuItem(value: id, child: Text(label));
                            }),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _selectedDoctorId = val;
                            });
                          },
                        ),
                        const SizedBox(height: 20),

                        // Section Header: Our Product vs Competitor
                        Text(
                          'Brand Comparison',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Colors.teal.shade800,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Our Brand
                        DropdownButtonFormField<Map<String, dynamic>>(
                          initialValue: _selectedOurItem,
                          decoration: InputDecoration(
                            labelText: 'Our Moonford Brand *',
                            prefixIcon: const Icon(Icons.medication),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          items: _catalogItems.map((item) {
                            final name = item['name']?.toString() ?? 'Item';
                            final price = (item['salePrice'] as num?)?.toDouble() ?? 0;
                            return DropdownMenuItem(
                              value: item,
                              child: Text('$name (₹${price.toStringAsFixed(0)})'),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedOurItem = val;
                            });
                          },
                          validator: (v) => v == null ? 'Select our product' : null,
                        ),
                        const SizedBox(height: 14),

                        // Competitor Brand Name
                        TextFormField(
                          controller: _competitorBrandCtl,
                          decoration: InputDecoration(
                            labelText: 'Competitor Brand Name *',
                            hintText: 'e.g. Augmentin 625, Calpol 650, Pan-D',
                            prefixIcon: const Icon(Icons.warning_amber_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Enter competitor brand name'
                              : null,
                        ),
                        const SizedBox(height: 14),

                        // Molecule / Generic Name
                        TextFormField(
                          controller: _moleculeCtl,
                          decoration: InputDecoration(
                            labelText: 'Molecule / Salt Name',
                            hintText: 'e.g. Amoxicillin + Clavulanate, Paracetamol',
                            prefixIcon: const Icon(Icons.science_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Numbers Row: Price + Monthly Volume
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _competitorPriceCtl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText: 'Competitor Rate (₹) *',
                                  hintText: 'e.g. 185',
                                  prefixText: '₹ ',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return 'Required';
                                  if (double.tryParse(v.trim()) == null) return 'Invalid';
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _monthlyQtyCtl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText: 'Monthly Rx Units *',
                                  hintText: 'e.g. 50 strips',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return 'Required';
                                  if (double.tryParse(v.trim()) == null) return 'Invalid';
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Remarks / Field Notes
                        TextFormField(
                          controller: _remarksCtl,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: 'Auditing Notes / Reason',
                            hintText: 'Doctor preference, stockist availability, distributor scheme...',
                            prefixIcon: const Icon(Icons.notes_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Submit Button
                        FilledButton.icon(
                          onPressed: _submitting ? null : _submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.teal.shade700,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: _submitting
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: const Text(
                            'Save RCPA Audit',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
