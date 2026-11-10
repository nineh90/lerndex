import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/main.dart';

void main() {
  test('Anmeldung über die eigene Domain nur auf app.lerndex.de', () {
    expect(webAuthDomainFor('app.lerndex.de'), 'app.lerndex.de');
    expect(webAuthDomainFor('lerndex-3775f.web.app'), isNull);
    expect(webAuthDomainFor('localhost'), isNull);
    expect(webAuthDomainFor(''), isNull);
  });
}
