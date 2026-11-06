import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/school/data/parent_link_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final saved = DateTime(2026, 11, 5, 10);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('frischer Code wird gelesen', () async {
    await PendingParentCode.remember('K7MXQ2PA', now: saved);
    expect(
      await PendingParentCode.read(now: saved.add(const Duration(hours: 3))),
      'K7MXQ2PA',
    );
  });

  test('nach einem Tag vergessen', () async {
    await PendingParentCode.remember('K7MXQ2PA', now: saved);
    expect(
      await PendingParentCode.read(
        now: saved.add(const Duration(days: 1, minutes: 1)),
      ),
      isNull,
    );
    // auch danach weg, nicht nur ausgeblendet
    expect(await PendingParentCode.read(now: saved), isNull);
  });

  test('alter Eintrag ohne Zeitstempel zählt als abgelaufen', () async {
    SharedPreferences.setMockInitialValues({'pending_parent_link': 'K7MXQ2PA'});
    expect(await PendingParentCode.read(now: saved), isNull);
  });

  test('clear löscht den Code', () async {
    await PendingParentCode.remember('K7MXQ2PA', now: saved);
    await PendingParentCode.clear();
    expect(await PendingParentCode.read(now: saved), isNull);
  });
}
