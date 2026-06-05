import 'package:flutter/material.dart';

import '../field/field_sample_data.dart';
import '../shared/field_widgets.dart';

class CollectionsScreen extends StatelessWidget {
  const CollectionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dueParties = sampleParties.where((party) => party.outstanding > 0);

    return PageScaffold(
      title: 'Collections',
      subtitle:
          'Record dealer payments, promises, and follow-ups from the field.',
      children: [
        ...dueParties.map(
          (party) => Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PartyCard(
                    party: party,
                    trailing: Text(
                      '₹${party.outstanding.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.event),
                          label: const Text('Promise'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.payments),
                          label: const Text('Collect'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
