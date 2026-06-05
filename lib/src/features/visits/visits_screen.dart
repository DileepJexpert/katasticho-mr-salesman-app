import 'package:flutter/material.dart';

import '../field/field_sample_data.dart';
import '../field/field_models.dart';
import '../shared/field_widgets.dart';

class VisitsScreen extends StatelessWidget {
  const VisitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Visits',
      subtitle:
          'Geo-verified check-ins for doctors, hospitals, chemists, distributors, and retailers.',
      children: sampleVisits
          .map(
            (visit) => Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PartyCard(
                      party: visit.party,
                      trailing: _StatusPill(status: visit.status),
                    ),
                    const SizedBox(height: 8),
                    Text(visit.objective),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.location_on),
                            label: const Text('Check in'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.edit_note),
                            label: const Text('Record'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final VisitStatus status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      VisitStatus.planned => 'Planned',
      VisitStatus.checkedIn => 'In visit',
      VisitStatus.completed => 'Done',
      VisitStatus.skipped => 'Skipped',
    };
    return Chip(label: Text(label));
  }
}
