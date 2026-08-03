import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/services/daily_prompt_service.dart';

void main() {
  const service = DailyPromptService();

  test('returns a non-empty prompt for any date', () {
    for (final date in [
      DateTime(2026, 1, 1),
      DateTime(2026, 8, 3),
      DateTime(2027, 12, 31),
    ]) {
      expect(service.promptFor(date), isNotEmpty);
    }
  });

  test('same date always returns same prompt (deterministic)', () {
    final date = DateTime(2026, 8, 3);
    expect(service.promptFor(date), service.promptFor(date));
  });

  test('consecutive days rotate prompts', () {
    final day1 = DateTime(2026, 8, 3);
    final day2 = DateTime(2026, 8, 4);
    expect(service.promptFor(day1), isNot(service.promptFor(day2)));
  });

  test('rotates after full cycle of 50 days', () {
    final start = DateTime(2026, 1, 1);
    final afterCycle = DateTime(2026, 2, 20); // 50 days later
    expect(service.promptFor(start), service.promptFor(afterCycle));
  });
}
