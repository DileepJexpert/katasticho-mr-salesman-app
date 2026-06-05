import 'package:flutter/material.dart';

import '../field/field_sample_data.dart';
import '../shared/field_widgets.dart';

class PartiesScreen extends StatelessWidget {
  const PartiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Parties',
      subtitle:
          'Doctors, hospitals, chemists, retailers, distributors, and stockists in one list.',
      children: [
        const TextField(
          decoration: InputDecoration(
            hintText: 'Search name, area, phone',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 12),
        ...sampleParties.map(
          (party) => PartyCard(
            party: party,
            trailing: party.outstanding > 0
                ? Text(
                    '₹${party.outstanding.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: Color(0xFFDC2626),
                      fontWeight: FontWeight.w800,
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}
