import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/off_const.dart';

/// The web build cannot call Open Food Facts directly (no CORS headers), so it
/// asks its own Worker at `/api/off/<host><path>`. The Worker only forwards
/// paths it knows (worker/src/index.js); these pin the shape both sides agree
/// on.
void main() {
  test('keeps the page origin and nests the OFF host under /api/off', () {
    final uri = OFFConst.webProxyUri(
      Uri.parse('https://app.example.com/?join=K7QM2XPA#/main'),
      'search.openfoodfacts.org',
      '/search',
      {'q': 'борщ', 'page': '1'},
    );

    expect(uri.origin, 'https://app.example.com');
    expect(uri.path, '/api/off/search.openfoodfacts.org/search');
    expect(uri.queryParameters, {'q': 'борщ', 'page': '1'});
    expect(uri.fragment, isEmpty);
  });

  test('keeps a development port', () {
    final uri = OFFConst.webProxyUri(
      Uri.parse('http://localhost:8787/'),
      'world.openfoodfacts.org',
      '/api/v2/product/737628064502',
      {'json': 'true'},
    );

    expect(
      uri.toString(),
      'http://localhost:8787/api/off/world.openfoodfacts.org'
      '/api/v2/product/737628064502?json=true',
    );
  });

  test('off the web the URLs still go straight to Open Food Facts', () {
    expect(
      OFFConst.getOffWordSearchUrl('apple').host,
      'search.openfoodfacts.org',
    );
    expect(
      OFFConst.getOffBarcodeSearchUri('737628064502').host,
      'world.openfoodfacts.org',
    );
  });
}
