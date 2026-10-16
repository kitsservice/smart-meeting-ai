import 'package:flutter_test/flutter_test.dart';
import 'package:smart_meeting_ai/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApiService Tests', () {
    test('candidateBaseUrls returns non-empty list of valid URLs safely', () {
      final urls = ApiService.candidateBaseUrls;
      expect(urls.isNotEmpty, isTrue);
      expect(urls.any((u) => u.contains('http')), isTrue);
    });

    test('baseUrl returns a non-empty fallback URL without throwing', () {
      final base = ApiService.baseUrl;
      expect(base.isNotEmpty, isTrue);
      expect(base.startsWith('http'), isTrue);
    });
  });
}
