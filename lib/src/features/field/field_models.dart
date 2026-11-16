enum FieldProfile {
  pharmaMr,
  distributorSalesman,
  fmcgSalesman,
  collectionAgent,
  deliveryAgent,
}

extension FieldProfileX on FieldProfile {
  bool get isPharma => this == FieldProfile.pharmaMr;

  String get label => switch (this) {
        FieldProfile.pharmaMr => 'Pharma field team',
        FieldProfile.distributorSalesman => 'Distributor sales team',
        FieldProfile.fmcgSalesman => 'FMCG sales team',
        FieldProfile.collectionAgent => 'Collection team',
        FieldProfile.deliveryAgent => 'Delivery team',
      };
}

FieldProfile resolveFieldProfile({
  required String industry,
  required String businessType,
}) {
  final value = '$industry $businessType'.toUpperCase();
  if (value.contains('PHARMA') ||
      value.contains('MEDICAL') ||
      value.contains('HEALTH')) {
    return FieldProfile.pharmaMr;
  }
  if (value.contains('COLLECTION')) return FieldProfile.collectionAgent;
  if (value.contains('DELIVERY') || value.contains('LOGISTICS')) {
    return FieldProfile.deliveryAgent;
  }
  if (value.contains('DISTRIBUT') || value.contains('WHOLESAL')) {
    return FieldProfile.distributorSalesman;
  }
  return FieldProfile.fmcgSalesman;
}
enum PartyType {
  doctor,
  hospital,
  clinic,
  chemist,
  retailer,
  distributor,
  stockist,
}

enum VisitStatus { planned, checkedIn, completed, skipped }

class FieldParty {
  const FieldParty({
    required this.id,
    required this.name,
    required this.type,
    required this.area,
    required this.phone,
    required this.outstanding,
    required this.lastVisitText,
    required this.priority,
  });

  final String id;
  final String name;
  final PartyType type;
  final String area;
  final String phone;
  final double outstanding;
  final String lastVisitText;
  final String priority;
}

class FieldVisitPlan {
  const FieldVisitPlan({
    required this.id,
    required this.party,
    required this.window,
    required this.status,
    required this.objective,
  });

  final String id;
  final FieldParty party;
  final String window;
  final VisitStatus status;
  final String objective;
}

class SyncTask {
  const SyncTask({
    required this.title,
    required this.subtitle,
    required this.status,
  });

  final String title;
  final String subtitle;
  final String status;
}
