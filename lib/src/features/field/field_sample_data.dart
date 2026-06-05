import 'field_models.dart';

const sampleParties = [
  FieldParty(
    id: 'doctor-1',
    name: 'Dr. Meera Sharma',
    type: PartyType.doctor,
    area: 'Civil Lines',
    phone: '9876543210',
    outstanding: 0,
    lastVisitText: '12 days ago',
    priority: 'High Rx potential',
  ),
  FieldParty(
    id: 'hospital-1',
    name: 'Apex Care Hospital',
    type: PartyType.hospital,
    area: 'Sector 62',
    phone: '9811122233',
    outstanding: 0,
    lastVisitText: 'Never visited',
    priority: 'Institution lead',
  ),
  FieldParty(
    id: 'chemist-1',
    name: 'Life Pharmacy',
    type: PartyType.chemist,
    area: 'Parasia Road',
    phone: '9000012345',
    outstanding: 18400,
    lastVisitText: '5 days ago',
    priority: 'Collection due',
  ),
  FieldParty(
    id: 'dist-1',
    name: 'Shree Pharma Distributor',
    type: PartyType.distributor,
    area: 'Main Market',
    phone: '9123456780',
    outstanding: 72500,
    lastVisitText: 'Yesterday',
    priority: 'Stock review',
  ),
];

final sampleVisits = [
  FieldVisitPlan(
    id: 'visit-1',
    party: sampleParties[0],
    window: '10:00 - 10:30',
    status: VisitStatus.planned,
    objective: 'Discuss Gastro portfolio and refill prescription trend.',
  ),
  FieldVisitPlan(
    id: 'visit-2',
    party: sampleParties[2],
    window: '12:00 - 12:30',
    status: VisitStatus.planned,
    objective: 'Collect overdue and book Crocin/Dolo replenishment.',
  ),
  FieldVisitPlan(
    id: 'visit-3',
    party: sampleParties[1],
    window: '15:00 - 16:00',
    status: VisitStatus.planned,
    objective: 'Meet purchase officer and capture tender opportunity.',
  ),
];

const sampleSyncTasks = [
  SyncTask(
    title: 'Visit check-in',
    subtitle: 'Dr. Meera Sharma',
    status: 'Ready',
  ),
  SyncTask(
    title: 'Collection draft',
    subtitle: 'Life Pharmacy - Rs 8,000',
    status: 'Offline',
  ),
  SyncTask(
    title: 'Location ping',
    subtitle: 'Last captured 2 min ago',
    status: 'Queued',
  ),
];
