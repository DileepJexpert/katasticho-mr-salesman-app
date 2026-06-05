enum FieldProfile {
  pharmaMr,
  distributorSalesman,
  fmcgSalesman,
  collectionAgent,
  deliveryAgent,
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
