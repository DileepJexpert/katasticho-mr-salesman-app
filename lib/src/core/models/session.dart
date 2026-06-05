class FieldSession {
  const FieldSession({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.orgId,
    required this.fullName,
    required this.role,
    required this.orgName,
    required this.industry,
    required this.businessType,
  });

  final String accessToken;
  final String refreshToken;
  final String userId;
  final String orgId;
  final String fullName;
  final String role;
  final String orgName;
  final String industry;
  final String businessType;

  bool get isDemo => accessToken == 'demo-token';

  factory FieldSession.fromAuthPayload(Map<String, dynamic> payload) {
    final user = payload['user'] as Map<String, dynamic>? ?? {};
    return FieldSession(
      accessToken: payload['accessToken'] as String? ?? '',
      refreshToken: payload['refreshToken'] as String? ?? '',
      userId: user['id'] as String? ?? '',
      orgId: user['orgId'] as String? ?? '',
      fullName: user['fullName'] as String? ?? 'Field user',
      role: user['role'] as String? ?? 'FIELD_SALES',
      orgName: user['orgName'] as String? ?? 'Katasticho',
      industry: user['industry'] as String? ?? '',
      businessType: user['businessType'] as String? ?? '',
    );
  }

  Map<String, String> toStorage() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'userId': userId,
    'orgId': orgId,
    'fullName': fullName,
    'role': role,
    'orgName': orgName,
    'industry': industry,
    'businessType': businessType,
  };

  factory FieldSession.fromStorage(Map<String, String> values) => FieldSession(
    accessToken: values['accessToken'] ?? '',
    refreshToken: values['refreshToken'] ?? '',
    userId: values['userId'] ?? '',
    orgId: values['orgId'] ?? '',
    fullName: values['fullName'] ?? 'Field user',
    role: values['role'] ?? 'FIELD_SALES',
    orgName: values['orgName'] ?? 'Katasticho',
    industry: values['industry'] ?? '',
    businessType: values['businessType'] ?? '',
  );

  static FieldSession demo() => const FieldSession(
    accessToken: 'demo-token',
    refreshToken: 'demo-refresh-token',
    userId: 'demo-user',
    orgId: 'demo-org',
    fullName: 'Demo MR',
    role: 'FIELD_SALES',
    orgName: 'Katasticho Pharma',
    industry: 'PHARMA',
    businessType: 'MANUFACTURER',
  );
}
