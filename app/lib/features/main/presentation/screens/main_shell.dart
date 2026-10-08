import 'package:flutter/material.dart';

import 'package:dialabsetest/core/theme/app_colors.dart';
import 'package:dialabsetest/features/auth/data/auth_repository.dart';
import 'package:dialabsetest/features/auth/data/auth_session.dart';
import 'package:dialabsetest/features/auth/presentation/screens/login_screen.dart';
import 'package:dialabsetest/features/home/presentation/screens/home_screen.dart';
import 'package:dialabsetest/features/profile/presentation/screens/profile_screen.dart';
import 'package:dialabsetest/features/users/presentation/screens/users_screen.dart';
import 'package:dialabsetest/features/calling/data/call_controller.dart';
import 'package:dialabsetest/features/calling/presentation/screens/call_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.session});

  final AuthSession session;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  late final CallController _calls;
  MaterialPageRoute<void>? _callRoute;
  ActiveCall? _shownCall;
  int _historyRevision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _calls = CallController(session: widget.session)
      ..addListener(_onCallChanged);
    _calls.start();
  }

  void _onCallChanged() {
    if (!mounted) return;
    final call = _calls.active;
    if (call != null && call != _shownCall) {
      _shownCall = call;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _calls.active == call) _openCall();
      });
    } else if (call == null && _shownCall != null) {
      final ended = _shownCall!;
      _shownCall = null;
      final route = _callRoute;
      _callRoute = null;
      if (route != null) Navigator.of(context).removeRoute(route);
      ended.historyQueue.whenComplete(() {
        if (mounted) setState(() => _historyRevision++);
      });
      if (_calls.error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_calls.error!)));
      }
    }
    setState(() {});
  }

  void _openCall() {
    if (_callRoute != null || _calls.active == null) return;
    final route = MaterialPageRoute<void>(
      builder: (_) => CallScreen(controller: _calls),
    );
    _callRoute = route;
    Navigator.of(context).push(route).whenComplete(() {
      if (_callRoute == route) _callRoute = null;
      if (mounted) setState(() {});
    });
  }

  void _callRecent(Map<String, dynamic> history) {
    final peerId = history['peer_user_id']?.toString();
    String? message;
    if (_calls.active != null) {
      message = 'End your current call before starting another.';
    } else if (!_calls.ready) {
      message = 'Calling is still connecting. Please try again shortly.';
    } else if (peerId == null) {
      message = 'This contact is no longer available.';
    } else if (!_calls.presence.callable(peerId)) {
      message = 'This user is offline or unavailable for a call.';
    }
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    _calls.call({
      'id': peerId,
      'name': history['peer_name']?.toString() ?? 'Unknown caller',
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _calls.removeListener(_onCallChanged);
    _calls.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _calls.signaling.connect();
      _calls.presence.connect();
      if (_calls.ready) {
        _calls.signaling.ensureFresh().catchError((Object _) {});
      }
    }
  }

  Future<void> _signOut() async {
    _calls.end();
    try {
      await authRepository.logout();
    } catch (_) {}
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          if (_calls.active != null)
            SafeArea(
              bottom: false,
              child: Material(
                color: const Color(0xFF344C46),
                child: ListTile(
                  textColor: Colors.white,
                  iconColor: Colors.white,
                  leading: const Icon(Icons.call),
                  title: Text(_calls.active!.peerName),
                  subtitle: Text(
                    _calls.active!.phase == CallPhase.connected
                        ? _calls.duration
                        : 'Call in progress',
                  ),
                  onTap: _openCall,
                  trailing: IconButton(
                    tooltip: 'End call',
                    onPressed: _calls.end,
                    icon: const Icon(Icons.call_end),
                  ),
                ),
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: [
                HomeScreen(
                  key: ValueKey(_historyRevision),
                  session: widget.session,
                  onCall: _callRecent,
                ),
                UsersScreen(calls: _calls),
                ProfileScreen(
                  name:
                      widget.session.user['name'] as String? ?? 'Dialbase user',
                  email: widget.session.user['email'] as String? ?? '',
                  onSignOut: _signOut,
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        height: 88,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _BottomNavItem(
              label: 'Home',
              icon: Icons.home_rounded,
              selected: _currentIndex == 0,
              onTap: () => setState(() => _currentIndex = 0),
            ),
            _BottomNavItem(
              label: 'Users',
              icon: Icons.group_rounded,
              selected: _currentIndex == 1,
              onTap: () => setState(() => _currentIndex = 1),
            ),
            _BottomNavItem(
              label: 'Profile',
              icon: Icons.person_rounded,
              selected: _currentIndex == 2,
              onTap: () => setState(() => _currentIndex = 2),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 90,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 28,
              color: selected ? AppColors.primary : const Color(0xFF6A6A6A),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.primary : const Color(0xFF6A6A6A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
