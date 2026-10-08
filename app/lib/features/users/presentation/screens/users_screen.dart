import 'package:flutter/material.dart';

import 'package:dialabsetest/core/theme/app_colors.dart';
import 'package:dialabsetest/features/calling/data/call_controller.dart';

class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key, required this.calls});
  final CallController calls;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: calls,
    builder: (context, _) => Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Users',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: calls.loadingUsers ? null : calls.loadUsers,
                    tooltip: 'Refresh users',
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (calls.error != null || calls.signaling.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    calls.error ?? calls.signaling.error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              if (!calls.presence.connected)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('Connecting to online users...'),
                ),
              Expanded(
                child: calls.loadingUsers && calls.users.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: calls.loadUsers,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            if (calls.users.isEmpty)
                              const Padding(
                                padding: EdgeInsets.only(top: 48),
                                child: Center(
                                  child: Text('No other users yet.'),
                                ),
                              ),
                            ...calls.users.map((user) {
                              final id = user['id'].toString();
                              final name = user['name'] as String;
                              final online = calls.presence.members.containsKey(
                                id,
                              );
                              final available = calls.presence.callable(id);
                              final busy =
                                  calls.presence.availability[id]?.busy == true;
                              final status = !calls.presence.connected
                                  ? 'Status unavailable'
                                  : !online
                                  ? 'Offline'
                                  : busy
                                  ? 'In a call'
                                  : available
                                  ? 'Online'
                                  : 'Connecting';
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                leading: CircleAvatar(
                                  radius: 28,
                                  backgroundColor: const Color(0xFF344C46),
                                  child: Text(
                                    name.isEmpty
                                        ? '?'
                                        : name.characters.first.toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  name,
                                  style: const TextStyle(fontSize: 22),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  status,
                                  style: TextStyle(
                                    color: available
                                        ? AppColors.primary
                                        : Colors.grey.shade700,
                                  ),
                                ),
                                trailing: IconButton(
                                  tooltip: 'Call $name',
                                  icon: const Icon(Icons.call),
                                  color: AppColors.primary,
                                  onPressed:
                                      calls.ready &&
                                          calls.active == null &&
                                          available
                                      ? () => calls.call(user)
                                      : null,
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
