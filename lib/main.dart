import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/print_job.dart';
import 'screens/designer_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/printer_screen.dart';
import 'screens/profile_screen.dart';
import 'services/notification_store.dart';
import 'theme.dart';

// =====================================================================
//  Signtech File Sharing — Flutter (Dart) Windows app
//
//  4 ta PC, sob Windows, same WiFi / LAN, internet lage na:
//    Designer PC 1, Designer PC 2,
//    Printer PC 1 = Human Y-Jet, Printer PC 2 = Challenger
//
//  Designer upload-er somoy printer beche ney (Y-Jet / Challenger),
//  file sorasori oi printer PC-te jay. Printer PC-te server chole
//  (port 8080), file Documents/Signtech File Sharing/Incoming/
//  <Printer>/ folder-e joma hoy, operator RIP khule print dey.
//  Vul printer-e gele operator ek click-e arek printer-e forward
//  korte pare.
//
//  Theme: professional Dark & Light (SigntechTheme) — AppBar-er
//  sun/moon button-e bodlay, pochondo save thake.
//
//  Build: GitHub Actions, Flutter 3.24.5, windows-2022 runner,
//  Inno Setup installer — .github/workflows/build.yml dekho.
// =====================================================================

const String _kRole = 'signtech_role';
const String _kDesignerName = 'signtech_designer_name';
const String _kYJetIp = 'signtech_yjet_ip';
const String _kChallengerIp = 'signtech_challenger_ip';
const String _kTheme = 'signtech_theme'; // 'dark' | 'light'

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SigntechFileSharingApp());
}

class SigntechFileSharingApp extends StatefulWidget {
  const SigntechFileSharingApp({super.key});

  @override
  State<SigntechFileSharingApp> createState() =>
      _SigntechFileSharingAppState();
}

class _SigntechFileSharingAppState extends State<SigntechFileSharingApp> {
  ThemeMode _mode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kTheme);
    if (mounted && saved == 'light') {
      setState(() => _mode = ThemeMode.light);
    }
  }

  Future<void> _toggleTheme() async {
    final next =
        _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kTheme, next == ThemeMode.light ? 'light' : 'dark');
    if (mounted) setState(() => _mode = next);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Signtech File Sharing',
      debugShowCheckedModeBanner: false,
      theme: SigntechTheme.light,
      darkTheme: SigntechTheme.dark,
      themeMode: _mode,
      home: HomePage(
        isDark: _mode == ThemeMode.dark,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
  });

  final bool isDark;
  final VoidCallback onToggleTheme;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  SharedPreferences? _prefs;
  String? _role; // designer | yjet | challenger
  String _designerName = '';
  String _yJetIp = '';
  String _challengerIp = '';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    // Load saved notifications so the bell badge is correct.
    NotificationStore.instance.load();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _prefs = prefs;
        _role = prefs.getString(_kRole);
        _designerName = prefs.getString(_kDesignerName) ?? '';
        _yJetIp = prefs.getString(_kYJetIp) ?? '';
        _challengerIp = prefs.getString(_kChallengerIp) ?? '';
      });
    }
  }

  Future<void> _setRole(String role) async {
    await _prefs?.setString(_kRole, role);
    if (mounted) setState(() => _role = role);
  }

  Future<void> _changeRole() async {
    await _prefs?.remove(_kRole);
    if (mounted) {
      setState(() => _role = null);
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _openProfile() {
    final isDesigner = _role == 'designer';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProfileScreen(
          roleLabel: _roleLabel,
          isDesigner: isDesigner,
          designerName: _designerName,
          yJetIp: _yJetIp,
          challengerIp: _challengerIp,
          otherPrinterLabel: _role == 'yjet'
              ? PrinterTarget.challenger.label
              : PrinterTarget.yJet.label,
          otherPrinterIp: _role == 'yjet' ? _challengerIp : _yJetIp,
          onDesignerNameChanged: (v) async {
            await _prefs?.setString(_kDesignerName, v);
            if (mounted) setState(() => _designerName = v);
          },
          onPrinterIpChanged: (printer, ip) async {
            await _prefs?.setString(
              printer == PrinterTarget.yJet ? _kYJetIp : _kChallengerIp,
              ip,
            );
            if (mounted) {
              setState(() {
                if (printer == PrinterTarget.yJet) {
                  _yJetIp = ip;
                } else {
                  _challengerIp = ip;
                }
              });
            }
          },
          onOtherPrinterIpChanged: (ip) async {
            await _prefs?.setString(
              _role == 'yjet' ? _kChallengerIp : _kYJetIp,
              ip,
            );
            if (mounted) {
              setState(() {
                if (_role == 'yjet') {
                  _challengerIp = ip;
                } else {
                  _yJetIp = ip;
                }
              });
            }
          },
          onChangeRole: _changeRole,
        ),
      ),
    );
  }

  String get _roleLabel {
    switch (_role) {
      case 'designer':
        return 'Designer PC';
      case 'yjet':
        return 'Printer PC — Human Y-Jet';
      case 'challenger':
        return 'Printer PC — Challenger';
      default:
        return 'Signtech File Sharing';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_prefs == null) {
      return const Scaffold(
        body: Center(
            child: CircularProgressIndicator(color: SigntechTheme.brandBlue)),
      );
    }
    // The printer dashboard has its own sidebar (profile, IP,
    // theme + profile buttons) — no top bar there.
    final isPrinter = _role == 'yjet' || _role == 'challenger';
    return Scaffold(
      appBar: isPrinter
          ? null
          : AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/logo.png',
                    width: 30,
                    height: 30,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 10),
                const Text('Signtech File Sharing'),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: Text(
                _roleLabel,
                style: TextStyle(
                    fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        actions: [
          if (_role == 'designer')
            ListenableBuilder(
              listenable: NotificationStore.instance,
              builder: (context, _) {
                final unread = NotificationStore.instance.unreadCount;
                return IconButton(
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.notifications),
                      if (unread > 0)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            constraints: const BoxConstraints(minWidth: 16),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$unread',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  tooltip: 'Notifications',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NotificationsScreen(),
                      ),
                    );
                  },
                );
              },
            ),
          IconButton(
            icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode),
            tooltip: widget.isDark ? 'Light theme' : 'Dark theme',
            onPressed: widget.onToggleTheme,
          ),
          if (_role != null)
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Profile / Settings',
              onPressed: _openProfile,
            ),
        ],
      ),
      body: _role == null
          ? _RoleSelect(onPick: _setRole)
          : _role == 'designer'
              ? DesignerScreen(
                  designerName: _designerName,
                  yJetIp: _yJetIp,
                  challengerIp: _challengerIp,
                )
              : PrinterScreen(
                  printer: _role == 'yjet'
                      ? PrinterTarget.yJet
                      : PrinterTarget.challenger,
                  otherPrinterIp: _role == 'yjet'
                      ? _challengerIp
                      : _yJetIp,
                  isDark: widget.isDark,
                  onToggleTheme: widget.onToggleTheme,
                  onOpenProfile: _openProfile,
                  onOtherPrinterIpChanged: (ip) async {
                    await _prefs?.setString(
                      _role == 'yjet' ? _kChallengerIp : _kYJetIp,
                      ip,
                    );
                    if (mounted) {
                      setState(() {
                        if (_role == 'yjet') {
                          _challengerIp = ip;
                        } else {
                          _yJetIp = ip;
                        }
                      });
                    }
                  },
                ),
    );
  }
}

class _RoleSelect extends StatelessWidget {
  const _RoleSelect({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 12),
            Text(
              'What is this PC?',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Once chosen, it is remembered. You can change it later in Settings (gear icon).',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            _RoleCard(
              icon: Icons.design_services,
              title: 'Designer PC',
              subtitle:
                  'Uploads files — chooses a printer (Y-Jet / Challenger) and sends',
              onTap: () => onPick('designer'),
            ),
            const SizedBox(height: 12),
            _RoleCard(
              icon: Icons.print,
              title: 'Printer PC — Human Y-Jet',
              subtitle: 'Opens received files in RIP and prints',
              onTap: () => onPick('yjet'),
            ),
            const SizedBox(height: 12),
            _RoleCard(
              icon: Icons.print,
              title: 'Printer PC — Challenger',
              subtitle: 'Opens received files in RIP and prints',
              onTap: () => onPick('challenger'),
            ),
            const SizedBox(height: 24),
            Text(
              'All PCs must be on the same WiFi. No internet needed.\nEnter the Printer PC IP once on the Designer PC.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: SigntechTheme.brandBlue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 28, color: SigntechTheme.brandBlue),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style:
                            TextStyle(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios,
                  size: 16, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
