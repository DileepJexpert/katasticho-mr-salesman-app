import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';

/// Monthly Tour Plan (MTP): the MR proposes next month's working day by
/// day, submits it, and the manager approves or rejects from the ERP.
class TourPlanScreen extends ConsumerStatefulWidget {
  const TourPlanScreen({super.key});

  @override
  ConsumerState<TourPlanScreen> createState() => _TourPlanScreenState();
}

class _TourPlanScreenState extends ConsumerState<TourPlanScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _plans = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final raw = await ref.read(apiClientProvider).getMyTourPlans();
      if (mounted) {
        setState(() =>
            _plans = raw.whereType<Map<String, dynamic>>().toList());
      }
    } catch (e) {
      _toast('Failed to load tour plans: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createPlan() async {
    final now = DateTime.now();
    final nextMonth = DateTime(now.year, now.month + 1, 1);
    final thisMonth = DateTime(now.year, now.month, 1);
    DateTime selected = nextMonth;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('New Tour Plan'),
          content: RadioGroup<DateTime>(
            groupValue: selected,
            onChanged: (v) => setDialogState(() => selected = v!),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<DateTime>(
                  title: Text(_monthLabel(thisMonth)),
                  value: thisMonth,
                ),
                RadioListTile<DateTime>(
                  title: Text(_monthLabel(nextMonth)),
                  value: nextMonth,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Create')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    try {
      final plan = await ref
          .read(apiClientProvider)
          .createTourPlan(_isoDate(selected));
      await _load();
      if (mounted) _openPlan(plan['id'].toString());
    } catch (e) {
      _toast('Failed to create plan: $e');
    }
  }

  void _openPlan(String planId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TourPlanDetailScreen(planId: planId),
      ),
    ).then((_) => _load());
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tour Plans')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createPlan,
        icon: const Icon(Icons.add),
        label: const Text('New Plan'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _plans.isEmpty
              ? const Center(child: Text('No tour plans yet'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _plans.length,
                    itemBuilder: (context, i) {
                      final plan = _plans[i];
                      final status = plan['status']?.toString() ?? 'DRAFT';
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.calendar_month),
                          title: Text(_monthLabel(
                              DateTime.parse(plan['planMonth'].toString()))),
                          subtitle: status == 'REJECTED' &&
                                  plan['rejectionReason'] != null
                              ? Text('Rejected: ${plan['rejectionReason']}')
                              : null,
                          trailing: _StatusChip(status: status),
                          onTap: () => _openPlan(plan['id'].toString()),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class TourPlanDetailScreen extends ConsumerStatefulWidget {
  const TourPlanDetailScreen({super.key, required this.planId});

  final String planId;

  @override
  ConsumerState<TourPlanDetailScreen> createState() =>
      _TourPlanDetailScreenState();
}

class _TourPlanDetailScreenState extends ConsumerState<TourPlanDetailScreen> {
  bool _loading = true;
  Map<String, dynamic>? _plan;
  List<Map<String, dynamic>> _entries = [];

  bool get _editable {
    final status = _plan?['status']?.toString();
    return status == 'DRAFT' || status == 'REJECTED';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final detail =
          await ref.read(apiClientProvider).getTourPlan(widget.planId);
      if (mounted) {
        setState(() {
          _plan = (detail['plan'] as Map?)?.cast<String, dynamic>();
          _entries = ((detail['entries'] as List?) ?? [])
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList();
        });
      }
    } catch (e) {
      _toast('Failed to load plan: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addEntry() async {
    final month = DateTime.parse(_plan!['planMonth'].toString());
    final lastDay = DateTime(month.year, month.month + 1, 0);
    DateTime? date = await showDatePicker(
      context: context,
      initialDate: month.isBefore(DateTime.now()) &&
              lastDay.isAfter(DateTime.now())
          ? DateTime.now()
          : month,
      firstDate: month,
      lastDate: lastDay,
    );
    if (date == null || !mounted) return;

    String activity = 'FIELD_WORK';
    final areaCtl = TextEditingController();
    final notesCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Plan for ${_isoDate(date)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: activity,
                decoration: const InputDecoration(labelText: 'Activity'),
                items: const [
                  DropdownMenuItem(
                      value: 'FIELD_WORK', child: Text('Field work')),
                  DropdownMenuItem(value: 'MEETING', child: Text('Meeting')),
                  DropdownMenuItem(value: 'OFFICE', child: Text('Office')),
                  DropdownMenuItem(value: 'CAMP', child: Text('Camp / CME')),
                  DropdownMenuItem(value: 'LEAVE', child: Text('Leave')),
                ],
                onChanged: (v) =>
                    setDialogState(() => activity = v ?? 'FIELD_WORK'),
              ),
              TextField(
                controller: areaCtl,
                decoration:
                    const InputDecoration(labelText: 'Area / HQ / Station'),
              ),
              TextField(
                controller: notesCtl,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    try {
      await ref.read(apiClientProvider).addTourPlanEntry(widget.planId, {
        'planDate': _isoDate(date),
        'activityType': activity,
        if (areaCtl.text.isNotEmpty) 'area': areaCtl.text.trim(),
        if (notesCtl.text.isNotEmpty) 'notes': notesCtl.text.trim(),
      });
      await _load();
    } catch (e) {
      _toast('Failed to add entry: $e');
    }
  }

  Future<void> _removeEntry(String entryId) async {
    try {
      await ref.read(apiClientProvider).removeTourPlanEntry(entryId);
      await _load();
    } catch (e) {
      _toast('Failed to remove entry: $e');
    }
  }

  Future<void> _submit() async {
    try {
      await ref.read(apiClientProvider).submitTourPlan(widget.planId);
      _toast('Tour plan submitted for approval');
      await _load();
    } catch (e) {
      _toast('Submit failed: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final status = _plan?['status']?.toString() ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(_plan != null
            ? _monthLabel(DateTime.parse(_plan!['planMonth'].toString()))
            : 'Tour Plan'),
        actions: [if (_plan != null) _StatusChip(status: status)],
      ),
      floatingActionButton: _editable
          ? FloatingActionButton.extended(
              onPressed: _addEntry,
              icon: const Icon(Icons.add),
              label: const Text('Add Day'),
            )
          : null,
      bottomNavigationBar: _editable && _entries.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.send),
                  label: const Text('Submit for Approval'),
                ),
              ),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (status == 'REJECTED' && _plan?['rejectionReason'] != null)
                  Container(
                    width: double.infinity,
                    color: Colors.red.shade50,
                    padding: const EdgeInsets.all(12),
                    child: Text('Rejected: ${_plan!['rejectionReason']}',
                        style: TextStyle(color: Colors.red.shade800)),
                  ),
                Expanded(
                  child: _entries.isEmpty
                      ? const Center(child: Text('No days planned yet'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _entries.length,
                          itemBuilder: (context, i) {
                            final e = _entries[i];
                            return Card(
                              child: ListTile(
                                leading: const Icon(Icons.event),
                                title: Text(
                                    '${e['planDate']} — ${e['activityType']}'),
                                subtitle: Text([e['area'], e['notes']]
                                    .where((x) =>
                                        x != null &&
                                        x.toString().trim().isNotEmpty)
                                    .join(' • ')),
                                trailing: _editable
                                    ? IconButton(
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () => _removeEntry(
                                            e['id'].toString()),
                                      )
                                    : null,
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'APPROVED' => Colors.green,
      'SUBMITTED' => Colors.orange,
      'REJECTED' => Colors.red,
      _ => Colors.grey,
    };
    return Chip(
      label: Text(status, style: const TextStyle(fontSize: 11)),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: color),
      visualDensity: VisualDensity.compact,
    );
  }
}

String _isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _monthLabel(DateTime d) {
  const names = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return '${names[d.month - 1]} ${d.year}';
}
