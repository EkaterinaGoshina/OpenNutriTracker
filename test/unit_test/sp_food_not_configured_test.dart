import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/sp_food_data_source.dart';
import 'package:opennutritracker/features/add_meal/data/dto/sp/sp_const.dart';

void main() {
  test('the .env.example placeholder is not a backend address', () {
    expect(SPConst.isBackendUrl('PROJECT_URL'), isFalse);
    expect(SPConst.isBackendUrl(''), isFalse);
    expect(SPConst.isBackendUrl('https://ref.supabase.co'), isTrue);
    expect(SPConst.isBackendUrl('http://localhost:54321'), isTrue);
  });

  test('an unconfigured backend answers at once with no foods', () async {
    // No SupabaseClient is registered: reaching for one would throw.
    final source = SpFoodDataSource(isConfigured: false);
    final elapsed = Stopwatch()..start();

    expect(await source.fetchSearchWordResults('творог'), isEmpty);
    expect(elapsed.elapsed, lessThan(const Duration(milliseconds: 500)));
  });
}
