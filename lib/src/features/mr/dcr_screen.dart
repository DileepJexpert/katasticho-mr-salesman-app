import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../auth/auth_controller.dart';
import '../shared/field_widgets.dart';

/// Daily Report (DCR): summarises today's visits — order bookings,
/// samples/promo given, and the doctor/chemist split when contacts are
/// classified — and submits the day for manager approval. Also shows the
/// computed TA/DA allowance and the salesperson's sample stock balance.
class DcrScreen extends ConsumerStatefulWidget {
  const DcrScreen({super.key});

  @override
  ConsumerState<DcrScreen> createState() => _DcrScreenState();
}

class _DcrScreenState extends ConsumerState<DcrScreen> {
  bool _loading = true;
  Map<String, dynamic>? _dcr;
  List<Map<String, dynamic>> _history = [];
  Map<String, dynamic>? _allowance;
  List<Map<String, dynamic>> _samples = [];
  String _workType = 'FIELD_WORK';
  final _remarksCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _remarksCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      final results = await Future.wait([
        api.buildDcr(),
        api.getMyDcrs(),
      ]);
      Map<String, dynamic>? allowance;
      List<Map<String, dynamic>> samples = [];
      try {
        allowance = await api.getMyAllowance();
        samples = (await api.getMySampleBalance())
            .whereType<Map<String, dynamic>>()
            .toList();
      } catch (_) {
        // allowance/samples are optional extras — never block the DCR
      }
      if (mounted) {
        setState(() {
          _dcr = results[0] as Map<String, dynamic>;
          _workType = _dcr?['workType']?.toString() ?? 'FIELD_WORK';
          _history = (results[1] as List)
              .whereType<Map<String, dynamic>>()
              .toList();
          _allowance = allowance;
          _samples = samples;
        });
      }
    } catch (e) {
      _toast('Failed to load DCR: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    try {
      await ref.read(apiClientProvider).submitDcr(
            workType: _workType,
            remarks: _remarksCtl.text.trim(),
          );
      _toast('DCR submitted');
      await _load();
    } catch (e) {
      _toast('Submit failed: $e');
    }
  }

  Future<void> _claimAllowance() async {
    final allowance = _allowance;
    if (allowance == null) return;

    double? km;
    final kmEditable = allowance['kmEditable'] == true;
    final manual = allowance['mode']?.toString() == 'MANUAL';
    if (kmEditable) {
      // Let the salesperson adjust the distance — e.g. deduct a personal
      // detour the GPS trail picked up. The GPS km stays on record for
      // the manager either way.
      final gpsKm = (allowance['distanceKm'] as num?)?.toDouble() ?? 0;
      final kmCtl =
          TextEditingController(text: manual ? '' : gpsKm.toStringAsFixed(1));
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Claim TA/DA'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!manual)
                Text('GPS recorded ${gpsKm.toStringAsFixed(1)} km today. '
                    'Adjust if some of it was personal travel.'),
              if (manual)
                const Text('Enter the distance you travelled for work today.'),
              const SizedBox(height: 8),
              TextField(
                controller: kmCtl,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Distance to claim (km)'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Claim')),
          ],
        ),
      );
      if (ok != true) return;
      km = double.tryParse(kmCtl.text);
      if (km == null) {
        _toast('Enter a valid distance in km');
        return;
      }
    }

    try {
      await ref.read(apiClientProvider).claimAllowance(km: km);
      _toast('Allowance claimed — expense recorded');
      await _load();
    } catch (e) {
      _toast('Claim failed: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  bool get _submittable {
    final status = _dcr?['status']?.toString();
    return status == 'DRAFT' || status == 'REJECTED';
  }

  @override
  Widget build(BuildContext context) {
    final status = _dcr?['status']?.toString() ?? 'DRAFT';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Report'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
              children: [
                SectionLabel(
                  "Today's summary",
                  trailing: Text(
                    status,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _statusColor(status),
                    ),
                  ),
                ),
                if (status == 'REJECTED' &&
                    _dcr?['rejectionReason'] != null) ...[
                  StatusStrip(
                    icon: Icons.cancel,
                    text: 'Rejected: ${_dcr!['rejectionReason']}',
                    color: Colors.red,
                  ),
                  const SizedBox(height: 8),
                ],
                MetricStrip(items: [
                  MetricItem('Visits', '${_dcr?['totalVisits'] ?? 0}'),
                  MetricItem('Orders ₹', '${_dcr?['totalPob'] ?? 0}'),
                  MetricItem('Samples', '${_dcr?['samplesGiven'] ?? 0}'),
                ]),
                if (((_dcr?['doctorsVisited'] as num?) ?? 0) > 0 ||
                    ((_dcr?['chemistsVisited'] as num?) ?? 0) > 0) ...[
                  const SizedBox(height: 8),
                  MetricStrip(items: [
                    MetricItem('Doctors', '${_dcr?['doctorsVisited'] ?? 0}'),
                    MetricItem('Chemists', '${_dcr?['chemistsVisited'] ?? 0}'),
                    MetricItem('Others', '${_dcr?['othersVisited'] ?? 0}'),
                  ]),
                ],
                if (_allowance != null &&
                    _allowance!['configured'] == true) ...[
                  const SectionLabel('TA / DA allowance'),
                  FlatList(children: [
                    FieldRow(
                      leading: const Icon(Icons.directions_car_outlined,
                          color: FieldUi.muted),
                      title: 'TA/DA ₹${_allowance!['totalAmount'] ?? 0}',
                      subtitle: '${_allowance!['distanceKm'] ?? 0} km travelled'
                          ' • TA ₹${_allowance!['taAmount'] ?? 0}'
                          ' + DA ₹${_allowance!['daAmount'] ?? 0}',
                      divider: false,
                      trailing: _allowance!['claimed'] == true
                          ? Text('CLAIMED',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.green.shade700,
                              ))
                          : FilledButton.tonal(
                              onPressed: _claimAllowance,
                              child: const Text('Claim'),
                            ),
                    ),
                  ]),
                ],
                if (_samples.isNotEmpty) ...[
                  const SectionLabel('My sample / promo stock'),
                  FlatList(
                    children: [
                      for (var i = 0; i < _samples.length; i++)
                        _sampleRow(_samples[i], i == _samples.length - 1),
                    ],
                  ),
                ],
                if (_submittable) ...[
                  const SectionLabel('Work type'),
                  DropdownButtonFormField<String>(
                    initialValue: _workType,
                    items: const [
                      DropdownMenuItem(
                          value: 'FIELD_WORK', child: Text('Field work')),
                      DropdownMenuItem(
                          value: 'MEETING', child: Text('Meeting')),
                      DropdownMenuItem(value: 'OFFICE', child: Text('Office')),
                      DropdownMenuItem(value: 'CAMP', child: Text('Camp / CME')),
                      DropdownMenuItem(value: 'LEAVE', child: Text('Leave')),
                    ],
                    onChanged: (v) =>
                        setState(() => _workType = v ?? 'FIELD_WORK'),
                  ),
                  const SectionLabel('Remarks'),
                  TextField(
                    controller: _remarksCtl,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.send),
                    label: const Text('Submit DCR'),
                  ),
                ],
                const SectionLabel('History'),
                if (_history.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                    child: Text('No reports yet.',
                        style: TextStyle(color: FieldUi.muted)),
                  )
                else
                  FlatList(
                    children: [
                      for (var i = 0; i < _history.length; i++)
                        _historyRow(_history[i], i == _history.length - 1),
                    ],
                  ),
              ],
            ),
    );
  }

  Widget _sampleRow(Map<String, dynamic> r, bool last) {
    final bal = (r['balance'] as num?) ?? 0;
    return FieldRow(
      title: r['productName']?.toString() ?? '',
      dense: true,
      divider: !last,
      trailing: Text(
        '$bal left',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: bal < 0 ? Colors.red : FieldUi.ink,
        ),
      ),
    );
  }

  Widget _historyRow(Map<String, dynamic> d, bool last) {
    return FieldRow(
      leading: const Icon(Icons.assignment_outlined, color: FieldUi.muted),
      title: '${d['reportDate']} — ${d['workType'] ?? ''}',
      subtitle: 'Visits ${d['totalVisits']} • POB ₹${d['totalPob']}'
          ' • Samples ${d['samplesGiven']}',
      divider: !last,
      trailing: Text(
        d['status']?.toString() ?? '',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _statusColor(d['status']?.toString()),
        ),
      ),
    );
  }

  Color _statusColor(String? status) {
    return switch (status) {
      'APPROVED' => Colors.green,
      'REJECTED' => Colors.red,
      'SUBMITTED' => Colors.orange,
      _ => FieldUi.muted,
    };
  }
}
