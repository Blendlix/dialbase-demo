import 'package:dialabsetest/features/auth/data/auth_session.dart';
import 'package:dialabsetest/features/home/data/call_history_repository.dart';
import 'package:dialabsetest/features/home/presentation/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class RecentCallsRepository extends CallHistoryRepository {
  @override
  Future<List<Map<String, dynamic>>> fetchCalls({
    required String token,
  }) async => [
    {
      'id': 99,
      'peer_user_id': 42,
      'peer_name': 'Demo Contact',
      'status': 'ended',
      'duration_seconds': 12,
      'initiated_at': '2026-10-08T03:00:00',
    },
  ];
}

void main() {
  testWidgets(
    'name avatar status time and row spacing redial the history peer',
    (tester) async {
      Map<String, dynamic>? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            session: const AuthSession(token: 'demo', user: {'id': 1}),
            repository: RecentCallsRepository(),
            onCall: (call) => selected = call,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final target in [
      find.text('Demo Contact'),
      find.text('DC'),
        find.text('Connected · 0m 12s'),
        find.text('03:00'),
      ]) {
        selected = null;
        await tester.tap(target);
        expect(selected?['peer_user_id'], 42);
        expect(selected?['id'], 99);
      }
      selected = null;
      final row = tester.getRect(find.byType(InkWell));
      await tester.tapAt(Offset(row.center.dx, row.bottom - 4));
      expect(selected?['peer_user_id'], 42);
    },
  );
}
