# Katasticho Field

Mobile field-force app for pharma MR teams, distributor salesmen, FMCG salesmen, collection agents, and delivery agents.

## Product Direction

This app is intentionally generic field-force software, not only a GPS tracker.

It supports two first-class business modes:

- **Manufacturer MR mode**: doctor, hospital, clinic, chemist, stockist, and distributor visits; DCR, product discussion, samples, gifts, competitor notes, and POB.
- **Distributor salesman mode**: retailer/chemist visits, order booking, stock/scheme visibility, dealer collections, promises, and follow-ups.

## Backend Connection

The app connects to the existing Katasticho ERP backend.

Current auth endpoints:

- `POST /api/v1/auth/login`
- `POST /api/v1/auth/refresh`
- `GET /api/v1/auth/me`

Run against local backend:

```powershell
flutter run -d chrome --dart-define=ENV=dev --dart-define=API_BASE_URL=http://localhost:8080
```

The app stores the ERP access token and sends:

```http
Authorization: Bearer <accessToken>
X-Org-Id: <orgId>
```

## Required Main Backend Facade

Do not expose every ERP endpoint directly to field users. Add a narrow backend facade in the main Katasticho repo:

- `GET /api/v1/field/today`
- `GET /api/v1/field/dealers`
- `GET /api/v1/field/dealers/{id}`
- `POST /api/v1/field/visits/check-in`
- `POST /api/v1/field/visits/check-out`
- `POST /api/v1/field/orders`
- `POST /api/v1/field/collections`
- `POST /api/v1/field/location-pings`
- `GET /api/v1/field/sync/bootstrap`
- `POST /api/v1/field/sync/push`

The facade should reuse existing ERP services for contacts, sales orders, payments, inventory, schemes, credit policy, and workflow.

## MVP Screens

- Login
- Today route
- Visits
- Parties
- Orders
- Collections
- Expenses
- Offline sync queue

## Next Phase

Add the `fieldforce` backend module in the main ERP repository, then replace demo data with real API-backed repositories.
