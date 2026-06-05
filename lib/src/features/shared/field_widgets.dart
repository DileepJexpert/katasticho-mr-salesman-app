import 'package:flutter/material.dart';

import '../field/field_models.dart';

class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              height: 42,
              width: 42,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PartyCard extends StatelessWidget {
  const PartyCard({super.key, required this.party, this.trailing});

  final FieldParty party;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: _partyColor(party.type).withValues(alpha: 0.14),
              foregroundColor: _partyColor(party.type),
              child: Icon(_partyIcon(party.type)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    party.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text('${party.area} · ${_partyLabel(party.type)}'),
                  const SizedBox(height: 4),
                  Text(
                    '${party.priority} · Last visit ${party.lastVisitText}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            trailing ?? const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

String partyLabel(PartyType type) => _partyLabel(type);

String _partyLabel(PartyType type) {
  return switch (type) {
    PartyType.doctor => 'Doctor',
    PartyType.hospital => 'Hospital',
    PartyType.clinic => 'Clinic',
    PartyType.chemist => 'Chemist',
    PartyType.retailer => 'Retailer',
    PartyType.distributor => 'Distributor',
    PartyType.stockist => 'Stockist',
  };
}

IconData _partyIcon(PartyType type) {
  return switch (type) {
    PartyType.doctor => Icons.medical_services,
    PartyType.hospital => Icons.local_hospital,
    PartyType.clinic => Icons.health_and_safety,
    PartyType.chemist => Icons.local_pharmacy,
    PartyType.retailer => Icons.storefront,
    PartyType.distributor => Icons.warehouse,
    PartyType.stockist => Icons.inventory_2,
  };
}

Color _partyColor(PartyType type) {
  return switch (type) {
    PartyType.doctor => const Color(0xFF2563EB),
    PartyType.hospital => const Color(0xFFDC2626),
    PartyType.clinic => const Color(0xFF7C3AED),
    PartyType.chemist => const Color(0xFF059669),
    PartyType.retailer => const Color(0xFFF59E0B),
    PartyType.distributor => const Color(0xFF0891B2),
    PartyType.stockist => const Color(0xFF475569),
  };
}
