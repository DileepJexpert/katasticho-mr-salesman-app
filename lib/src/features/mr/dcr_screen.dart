import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';

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
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Today's summary",
                        style: Theme.of(context).textTheme.titleMedium),
                    Chip(
                      label: Text(status,
                          style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (status == 'REJECTED' &&
                    _dcr?['rejectionReason'] != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Rejected: ${_dcr!['rejectionReason']}',
                        style: TextStyle(color: Colors.red.shade800)),
                  ),
                  const SizedBox(height: 8),
                ],
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _Metric('Visits', '${_dcr?['totalVisits'] ?? 0}'),
                            _Metric('Orders ₹', '${_dcr?['totalPob'] ?? 0}'),
                            _Metric(
                                'Samples', '${_dcr?['samplesGiven'] ?? 0}'),
                          ],
                        ),
                        if (((_dcr?['doctorsVisited'] as num?) ?? 0) > 0 ||
                            ((_dcr?['chemistsVisited'] as num?) ?? 0) > 0) ...[
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _Metric('Doctors',
                                  '${_dcr?['doctorsVisited'] ?? 0}'),
                              _Metric('Chemists',
                                  '${_dcr?['chemistsVisited'] ?? 0}'),
                              _Metric('Others',
                                  '${_dcr?['othersVisited'] ?? 0}'),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_allowance != null &&
                    _allowance!['configured'] == true) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.directions_car_outlined),
                      title: Text(
                          'TA/DA: ₹${_allowance!['totalAmount'] ?? 0}'),
                      subtitle: Text(
                          '${_allowance!['distanceKm'] ?? 0} km travelled'
                          ' • TA ₹${_allowance!['taAmount'] ?? 0}'
                          ' + DA ₹${_allowance!['daAmount'] ?? 0}'),
                      trailing: _allowance!['claimed'] == true
                          ? const Chip(
                              label: Text('CLAIMED',
                                  style: TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                            )
                          : FilledButton.tonal(
                              onPressed: _claimAllowance,
                              child: const Text('Claim'),
                            ),
                    ),
                  ),
                ],
                if (_samples.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('My sample / promo stock',
                              style:
                                  Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 4),
                          ..._samples.map((r) {
                            final bal = (r['balance'] as num?) ?? 0;
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                      child: Text(
                                          r['productName']?.toString() ??
                                              '')),
                                  Text('$bal left',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color:
                                            bal < 0 ? Colors.red : null,
                                      )),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (_submittable) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _workType,
                    decoration: const InputDecoration(labelText: 'Work type'),
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
                  const SizedBox(height: 8),
                  TextField(
                    controller: _remarksCtl,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Remarks'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.send),
                    label: const Text('Submit DCR'),
                  ),
                ],
                const SizedBox(height: 24),
                Text('History', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ..._history.map((d) => Card(
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.assignment_outlined),
                        title: Text(
                            '${d['reportDate']} — ${d['workType'] ?? ''}'),
                        subtitle: Text(
                            'Visits ${d['totalVisits']} • POB ₹${d['totalPob']}'
                            ' • Samples ${d['samplesGiven']}'),
                        trailing: Text(d['status']?.toString() ?? '',
                            style: TextStyle(
                              fontSize: 11,
                              color: switch (d['status']?.toString()) {
                                'APPROVED' => Colors.green,
                                'REJECTED' => Colors.red,
                                'SUBMITTED' => Colors.orange,
                                _ => Colors.grey,
                              },
                            )),
                      ),
                    )),
              ],
            ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
