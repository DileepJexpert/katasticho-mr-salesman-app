import 'package:shared_preferences/shared_preferences.dart';

import '../models/session.dart';

class SessionStore {
  static const _prefix = 'field.session.';
  static const _keys = [
    'accessToken',
    'refreshToken',
    'userId',
    'orgId',
    'fullName',
    'role',
    'orgName',
    'industry',
    'businessType',
  ];

  Future<FieldSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('$_prefix.accessToken');
    if (accessToken == null || accessToken.isEmpty) return null;

    final values = <String, String>{};
    for (final key in _keys) {
      values[key] = prefs.getString('$_prefix.$key') ?? '';
    }
    return FieldSession.fromStorage(values);
  }

  Future<void> save(FieldSession session) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in session.toStorage().entries) {
      await prefs.setString('$_prefix.${entry.key}', entry.value);
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _keys) {
      await prefs.remove('$_prefix.$key');
    }
  }
}
