import 'package:mudbase_showcase_docs_search/models/mudbase_user.dart';
import 'package:test/test.dart';

void main() {
  group('MudbaseUser.fromJson', () {
    test('parses a real signed-in customer account', () {
      final user = MudbaseUser.fromJson({
        'id': '6a6d409a51703cd1071b46fe',
        'email': 'docs.member.demo@gmail.com',
        'firstName': 'Docs',
        'lastName': 'Member',
        'customRole': 'customer',
        'emailVerified': true,
        'isAnonymous': false,
      });

      expect(user.id, '6a6d409a51703cd1071b46fe');
      expect(user.fullName, 'Docs Member');
      expect(user.isAuthenticated, isTrue);
    });

    test('parses an anonymous guest session as not authenticated', () {
      final user = MudbaseUser.fromJson({
        'id': 'guest-1',
        'email': '',
        'isAnonymous': true,
        'customRole': null,
      });

      expect(user.isAnonymous, isTrue);
      expect(user.isAuthenticated, isFalse);
    });

    test('falls back to "_id" when "id" is absent', () {
      final user = MudbaseUser.fromJson({'_id': 'from-underscore-id'});
      expect(user.id, 'from-underscore-id');
    });

    test('a signed-in user with a null customRole is not authenticated', () {
      final user = MudbaseUser.fromJson({
        'id': 'x',
        'isAnonymous': false,
        'customRole': null,
      });
      expect(user.isAuthenticated, isFalse);
    });

    test('fullName falls back to email when both names are blank', () {
      final user = MudbaseUser.fromJson({'id': 'x', 'email': 'a@b.com'});
      expect(user.fullName, 'a@b.com');
    });
  });
}
