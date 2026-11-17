import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  static const _demoMoonfordMrPhone = '9000000029';
  static const _demoMoonfordMrPassword = 'Demo@1234';
  static const _demoMoonfordOwnerPhone = '9000000028';
  static const _demoMoonfordOwnerPassword = 'Demo@1234';
  static const _demoSalesmanPhone = '9000000005';
  static const _demoSalesmanPassword = 'Demo@1234';

  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _quickLogin(String phone, String password) async {
    _identifier.text = phone;
    _password.text = password;
    await ref.read(authControllerProvider.notifier).login(phone, password);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        height: 54,
                        width: 54,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF0B6B5E), Color(0xFF044E43)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0B6B5E).withValues(alpha: 0.25),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'K',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Katasticho Field',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const Text(
                              'AI-Native Pharma MR & Field Force Cockpit',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Sign In to Your Beat',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Geo-verified doctor detailing, chemist POBs, RCPA & instant collections.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                          const SizedBox(height: 18),
                          TextField(
                            controller: _identifier,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Mobile Number or Email',
                              hintText: 'e.g. 9000000029',
                              prefixIcon: Icon(Icons.phone_android_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _password,
                            obscureText: _obscurePassword,
                            onSubmitted: (_) {
                              if (!state.isLoading) {
                                ref
                                    .read(authControllerProvider.notifier)
                                    .login(_identifier.text.trim(), _password.text);
                              }
                            },
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  size: 20,
                                ),
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                              ),
                            ),
                          ),
                          if (state.error != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.error_outline, size: 18, color: Colors.red.shade700),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      state.error!,
                                      style: TextStyle(
                                        color: Colors.red.shade700,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: state.isLoading
                                  ? null
                                  : () => ref
                                        .read(authControllerProvider.notifier)
                                        .login(_identifier.text.trim(), _password.text),
                              icon: state.isLoading
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.login_rounded, size: 18),
                              label: Text(state.isLoading ? 'Signing in…' : 'Sign In'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Icon(Icons.flash_on_rounded, size: 16, color: Color(0xFF0B6B5E)),
                      const SizedBox(width: 6),
                      Text(
                        '1-CLICK INSTANT DEMO SIGN-IN',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _QuickRoleCard(
                    title: 'Amit Srivastava (Pharma MR — Bahraich HQ)',
                    subtitle: 'Moonford Pharma · Doctors, Chemists, POBs & RCPA (9000000029)',
                    icon: Icons.medical_services_outlined,
                    badgeColor: const Color(0xFF0B6B5E),
                    badgeBg: const Color(0xFFECFDF5),
                    enabled: !state.isLoading,
                    onTap: () => _quickLogin(_demoMoonfordMrPhone, _demoMoonfordMrPassword),
                  ),
                  const SizedBox(height: 8),
                  _QuickRoleCard(
                    title: 'Dr. M. K. Sharma (Moonford Pharma MD)',
                    subtitle: 'Head Office Manager · All Routes & Team Approvals (9000000028)',
                    icon: Icons.workspace_premium_outlined,
                    badgeColor: const Color(0xFF7E22CE),
                    badgeBg: const Color(0xFFF3E8FF),
                    enabled: !state.isLoading,
                    onTap: () => _quickLogin(_demoMoonfordOwnerPhone, _demoMoonfordOwnerPassword),
                  ),
                  const SizedBox(height: 8),
                  _QuickRoleCard(
                    title: 'FMCG Van & Beat Salesman',
                    subtitle: 'General Trade Distribution · Route Orders & Van Stock (9000000005)',
                    icon: Icons.local_shipping_outlined,
                    badgeColor: const Color(0xFF2563EB),
                    badgeBg: const Color(0xFFEFF6FF),
                    enabled: !state.isLoading,
                    onTap: () => _quickLogin(_demoSalesmanPhone, _demoSalesmanPassword),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: state.isLoading
                          ? null
                          : () => ref.read(authControllerProvider.notifier).startDemo(),
                      icon: const Icon(Icons.play_circle_outline, size: 18),
                      label: const Text('Explore Offline Sandbox Mode'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickRoleCard extends StatelessWidget {
  const _QuickRoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.badgeColor,
    required this.badgeBg,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color badgeColor;
  final Color badgeBg;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: badgeColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 14, color: badgeColor),
            ],
          ),
        ),
      ),
    );
  }
}
