import 'package:flutter_test/flutter_test.dart';
import 'package:task_status_reminder/main.dart';

void main() {
  testWidgets('Task Status Reminder starts', (tester) async {
    await tester.pumpWidget(const TaskStatusReminderApp());
    expect(find.text('مهامي الملوّنة'), findsOneWidget);
  });
}
