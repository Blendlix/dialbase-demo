import 'package:flutter/material.dart';

import 'package:dialabsetest/core/theme/app_colors.dart';
import 'package:dialabsetest/features/auth/data/auth_session.dart';
import 'package:dialabsetest/features/home/data/call_history_repository.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.session,
    required this.onCall,
    this.repository,
  });

  final AuthSession session;
  final ValueChanged<Map<String, dynamic>> onCall;
  final CallHistoryRepository? repository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final CallHistoryRepository _repository;
  late Future<List<Map<String, dynamic>>> _callsFuture;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? CallHistoryRepository();
    _callsFuture = _loadCalls();
  }

  Future<List<Map<String, dynamic>>> _loadCalls() {
    return _repository.fetchCalls(token: widget.session.token);
  }

  Future<void> _refreshCalls() async {
    final nextCalls = _loadCalls();
    setState(() => _callsFuture = nextCalls);
    try {
      await nextCalls;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              const Text(
                'Calls',
                style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _callsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          snapshot.error.toString(),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }

                    final calls = snapshot.data ?? [];
                    return RefreshIndicator(
                      onRefresh: _refreshCalls,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        children: [
                          const Text(
                            'Recent calls',
                            style: TextStyle(
                              fontSize: 18,
                              color: Color(0xFF5F6A68),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (calls.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 48),
                              child: Center(child: Text('No calls yet.')),
                            )
                          else
                            ...calls.map(
                              (call) => _CallRow(
                                call: call,
                                onTap: () => widget.onCall(call),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallRow extends StatelessWidget {
  const _CallRow({required this.call, required this.onTap});

  final Map<String, dynamic> call;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = call['peer_name']?.toString() ?? 'Unknown caller';
    final status = call['status']?.toString() ?? 'unknown';
    final connectedSeconds = call['duration_seconds'] as int? ?? 0;
    final initiatedAt = DateTime.tryParse(
      call['initiated_at']?.toString() ?? '',
    );
    final colors = [
      const Color(0xFFCF9D6B),
      const Color(0xFFABC5D8),
      const Color(0xFF9DC9F5),
      const Color(0xFFD4B5A3),
    ];
    final color = colors[(name.hashCode & 0x7fffffff) % colors.length];
    final initials = name
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    final statusLabel = switch (status) {
      'ended' => connectedSeconds > 0 ? 'Connected' : 'Ended',
      'missed' => 'Missed',
      'rejected' => 'Rejected',
      'canceled' => 'Canceled',
      'failed' => 'Failed',
      _ => status,
    };
    final statusIcon = switch (status) {
      'missed' || 'rejected' || 'failed' => Icons.call_missed_rounded,
      'canceled' => Icons.call_end_rounded,
      _ => Icons.call_made_rounded,
    };
    final isUnsuccessful =
        status == 'missed' || status == 'rejected' || status == 'failed';
    final time = initiatedAt == null
        ? ''
        : '${initiatedAt.toLocal().hour.toString().padLeft(2, '0')}:${initiatedAt.toLocal().minute.toString().padLeft(2, '0')}';
    final duration = connectedSeconds > 0
        ? ' · ${connectedSeconds ~/ 60}m ${connectedSeconds % 60}s'
        : '';

    return Semantics(
      button: true,
      label: 'Call $name',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: color,
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            statusIcon,
                            size: 18,
                            color: isUnsuccessful
                                ? Colors.red
                                : const Color(0xFF444444),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '$statusLabel$duration',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 18,
                                color: isUnsuccessful
                                    ? Colors.red
                                    : const Color(0xFF444444),
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Text(
                  time,
                  style: const TextStyle(
                    fontSize: 18,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
