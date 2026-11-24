import 'package:material_ui/material_ui.dart';

import '../services/auth_service.dart';
import '../models/models.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import 'profile_screen.dart';

// =========================================================================
// PALETA — espelha o design system do chat (Deep Indigo / neutros claros).
// =========================================================================
class SettingsColors {
  static bool get _dark => AppTheme.isDark;

  static Color get bg =>
      _dark ? const Color(0xFF0B0F1A) : const Color(0xFFF8FAFC);
  static Color get card => _dark
      ? const Color(0xFF111827).withValues(alpha: 0.85)
      : Colors.white.withValues(alpha: 0.85);
  static Color get accent =>
      _dark ? const Color(0xFF818CF8) : const Color(0xFF6366F1);
  static const violet = Color(0xFF8B5CF6);
  static Color get textHeader =>
      _dark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
  static Color get textNormal =>
      _dark ? const Color(0xFFCBD5E1) : const Color(0xFF334155);
  static Color get textMuted =>
      _dark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  static Color get divider =>
      _dark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
  static const red = Color(0xFFE11D48);
  static Color get border => _dark
      ? const Color(0xFF1E293B).withValues(alpha: 0.6)
      : Colors.white.withValues(alpha: 0.3);

  static List<BoxShadow> get softShadow => _dark
      ? [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ]
      : [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ];
}

/// =========================================================================
/// TELA DE CONFIGURAÇÕES — light glassmorphism, Deep Indigo (Linear/Notion).
/// =========================================================================
/// Seções em cards de vidro arredondados, ícones minimalistas em indigo,
/// switches funcionais (persistidos via SharedPreferences-like simples em
/// memória — troque por shared_preferences se quiser persistência real)
/// e logout com confirmação.
class SettingsScreen extends StatefulWidget {
  final String userId;
  const SettingsScreen({super.key, required this.userId});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Preferências (em memória; plugue shared_preferences para persistir).
  bool _notificationsOn = true;
  bool _soundOn = true;
  bool _showOnlineStatus = true;
  bool _readReceipts = true;
  bool _darkMode = AppTheme.isDark; // reflete o tema atual ao abrir

  final String _appVersion = '1.0.0';

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: SettingsColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Sair da conta',
            style: TextStyle(
                color: SettingsColors.textHeader,
                fontWeight: FontWeight.w800)),
        content: Text(
          'Você será desconectado e voltará para a tela de login.',
          style: TextStyle(color: SettingsColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child:
                const Text('Sair', style: TextStyle(color: SettingsColors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await AuthService.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SettingsColors.bg,
      appBar: AppBar(
        backgroundColor: SettingsColors.card, // vidro adaptativo
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: SettingsColors.textHeader,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Configurações',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // ================= PERFIL (atalho) =================
          _SettingsCard(
            child: StreamBuilder<Profile>(
              stream: ProfileService.watchMyProfile(widget.userId),
              builder: (context, snapshot) {
                final profile = snapshot.data;
                final name = profile?.displayName ?? '...';
                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ProfileScreen(
                        userId: widget.userId, isOwnProfile: true),
                  )),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: SettingsColors.accent, width: 2),
                        ),
                        child: CircleAvatar(
                          radius: 22,
                          backgroundColor: SettingsColors.accent,
                          backgroundImage: profile?.avatarUrl != null
                              ? NetworkImage(profile!.avatarUrl!)
                              : null,
                          child: profile?.avatarUrl == null
                              ? Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: TextStyle(
                                    color: SettingsColors.textHeader,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15)),
                            if (profile != null)
                              Text('@${profile.username}',
                                  style: TextStyle(
                                      color: SettingsColors.textMuted,
                                      fontSize: 12.5)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          color: SettingsColors.textMuted),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // ================= NOTIFICAÇÕES =================
          const _SectionLabel('Notificações'),
          _SettingsCard(
            child: Column(
              children: [
                _SwitchRow(
                  icon: Icons.notifications_rounded,
                  label: 'Notificações push',
                  subtitle: 'Receba avisos de novas mensagens',
                  value: _notificationsOn,
                  onChanged: (v) => setState(() => _notificationsOn = v),
                ),
                Divider(height: 1, color: SettingsColors.divider),
                _SwitchRow(
                  icon: Icons.volume_up_rounded,
                  label: 'Som das notificações',
                  subtitle: 'Toque ao receber mensagem',
                  value: _soundOn,
                  onChanged: (v) => setState(() => _soundOn = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ================= APARÊNCIA =================
          const _SectionLabel('Aparência'),
          _SettingsCard(
            child: Column(
              children: [
                _SwitchRow(
                  icon: Icons.dark_mode_rounded,
                  label: 'Modo escuro',
                  subtitle: 'Salvo automaticamente neste dispositivo',
                  value: _darkMode,
                  onChanged: (v) {
                    setState(() => _darkMode = v);
                    // Define E salva: persiste entre recarregadas e sessões.
                    AppTheme.setDark(v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ================= PRIVACIDADE =================
          const _SectionLabel('Privacidade e segurança'),
          _SettingsCard(
            child: Column(
              children: [
                _SwitchRow(
                  icon: Icons.circle_rounded,
                  label: 'Mostrar status online',
                  subtitle: 'Outros veem quando você está online',
                  value: _showOnlineStatus,
                  onChanged: (v) => setState(() => _showOnlineStatus = v),
                ),
                Divider(height: 1, color: SettingsColors.divider),
                _SwitchRow(
                  icon: Icons.done_all_rounded,
                  label: 'Confirmações de leitura',
                  subtitle: 'Avise quando ler as mensagens',
                  value: _readReceipts,
                  onChanged: (v) => setState(() => _readReceipts = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ================= SOBRE =================
          const _SectionLabel('Sobre o aplicativo'),
          _SettingsCard(
            child: Column(
              children: [
                _InfoRow(
                  icon: Icons.info_outline_rounded,
                  label: 'Versão',
                  value: _appVersion,
                ),
                Divider(height: 1, color: SettingsColors.divider),
                _LinkRow(
                  icon: Icons.description_outlined,
                  label: 'Termos de uso',
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Termos de uso em breve.'))),
                ),
                Divider(height: 1, color: SettingsColors.divider),
                _LinkRow(
                  icon: Icons.privacy_tip_outlined,
                  label: 'Política de privacidade',
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Política de privacidade em breve.'))),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ================= SAIR DA CONTA =================
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: SettingsColors.red.withValues(alpha: 0.35)),
              color: SettingsColors.card,
              boxShadow: SettingsColors.softShadow,
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _confirmLogout,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout_rounded,
                        color: SettingsColors.red, size: 20),
                    SizedBox(width: 8),
                    Text('Sair da conta',
                        style: TextStyle(
                            color: SettingsColors.red,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// =========================================================================
// COMPONENTES REUTILIZÁVEIS
// =========================================================================

/// Card de vidro: branco translúcido, raio 20, borda clara, sombra suave.
class _SettingsCard extends StatelessWidget {
  final Widget child;
  const _SettingsCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: SettingsColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SettingsColors.border),
        boxShadow: SettingsColors.softShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: child,
      ),
    );
  }
}

/// Rótulo de seção (uppercase, pequeno, cinza).
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 8),
      child: Text(text.toUpperCase(),
          style: TextStyle(
              color: SettingsColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6)),
    );
  }
}

/// Linha com ícone indigo + rótulo + Switch indigo.
class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: SettingsColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 19, color: SettingsColors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: SettingsColors.textHeader,
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5)),
                Text(subtitle,
                    style: TextStyle(
                        color: SettingsColors.textMuted, fontSize: 12.5)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.white,
            activeTrackColor: SettingsColors.accent,
            inactiveThumbColor: SettingsColors.textMuted,
            inactiveTrackColor: SettingsColors.divider,
          ),
        ],
      ),
    );
  }
}

/// Linha informativa (rótulo à esquerda, valor à direita).
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: SettingsColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 19, color: SettingsColors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: SettingsColors.textHeader,
                    fontWeight: FontWeight.w600,
                    fontSize: 14.5)),
          ),
          Text(value,
              style: TextStyle(
                  color: SettingsColors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }
}

/// Linha clicável (link) com seta.
class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _LinkRow(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: SettingsColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 19, color: SettingsColors.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: SettingsColors.textHeader,
                      fontWeight: FontWeight.w600,
                      fontSize: 14.5)),
            ),
            Icon(Icons.chevron_right_rounded,
                color: SettingsColors.textMuted),
          ],
        ),
      ),
    );
  }
}
