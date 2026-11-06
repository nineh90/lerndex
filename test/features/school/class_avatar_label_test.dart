import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/school/presentation/school_home_screen.dart';
import 'package:lerndex/src/shared/activity_tracker.dart';

void main() {
  test('kurze Klassennamen bleiben', () {
    expect(classAvatarLabel('5b'), '5b');
    expect(classAvatarLabel('10a'), '10a');
  });

  test('lange Namen werden zu Initialen', () {
    expect(classAvatarLabel('Sonnenklasse'), 'SO');
    expect(classAvatarLabel('Klasse 3 Füchse'), '3F');
    expect(classAvatarLabel('Klasse'), 'KL');
    expect(classAvatarLabel('  '), '?');
  });

  test('Inaktivität: erst nach Ablauf der Frist', () {
    final start = DateTime(2026, 11, 6, 8);
    ActivityTracker.touch(start);
    const limit = Duration(minutes: 30);
    expect(
      ActivityTracker.idleFor(
        limit,
        now: start.add(const Duration(minutes: 29)),
      ),
      isFalse,
    );
    expect(
      ActivityTracker.idleFor(
        limit,
        now: start.add(const Duration(minutes: 30)),
      ),
      isTrue,
    );
  });
}
