import 'field_models.dart';

const sampleParties = [
  FieldParty(
    id: 'retailer-1',
    name: 'Shree Kirana Store',
    type: PartyType.retailer,
    area: 'Civil Lines',
    phone: '9876543210',
    outstanding: 0,
    lastVisitText: '12 days ago',
    priority: 'High repeat potential',
  ),
  FieldParty(
    id: 'wholesale-1',
    name: 'Apex Wholesale Mart',
    type: PartyType.distributor,
    area: 'Sector 62',
    phone: '9811122233',
    outstanding: 0,
    lastVisitText: 'Never visited',
    priority: 'New outlet lead',
  ),
  FieldParty(
    id: 'retailer-2',
    name: 'Life General Store',
    type: PartyType.retailer,
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
    objective: 'Review masala, oil and grocery replenishment.',
  ),
  FieldVisitPlan(
    id: 'visit-2',
    party: sampleParties[2],
    window: '12:00 - 12:30',
    status: VisitStatus.planned,
    objective: 'Collect overdue and book grocery replenishment.',
  ),
  FieldVisitPlan(
    id: 'visit-3',
    party: sampleParties[1],
    window: '15:00 - 16:00',
    status: VisitStatus.planned,
    objective: 'Meet purchase officer and capture new outlet opportunity.',
  ),
];

const sampleSyncTasks = [
  SyncTask(
    title: 'Visit check-in',
    subtitle: 'Shree Kirana Store',
    status: 'Ready',
  ),
  SyncTask(
    title: 'Collection draft',
    subtitle: 'Life General Store - Rs 8,000',
    status: 'Offline',
  ),
  SyncTask(
    title: 'Location ping',
    subtitle: 'Last captured 2 min ago',
    status: 'Queued',
  ),
];
