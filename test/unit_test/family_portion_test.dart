import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/family/data/account_repository.dart';
import 'package:opennutritracker/features/family/data/family_portion_service.dart';
import 'package:opennutritracker/features/family/data/family_repository.dart';
import 'package:opennutritracker/features/family/domain/entity/family_entity.dart';
import 'package:opennutritracker/features/family/domain/entity/family_portion_entity.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../fixture/meal_entity_fixtures.dart';

User _user(String id) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
);

class _Account implements AccountRepository {
  @override
  User? currentUser;

  _Account(this.currentUser);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Families implements FamilyRepository {
  List<PendingPortion> pending = [];
  FamilyEntity? family;
  final marked = <List<String>>[];
  var failMark = false;

  @override
  Future<List<PendingPortion>> getPendingPortions(String userId) async =>
      pending;

  @override
  Future<FamilyEntity?> getMyFamily() async => family;

  @override
  Future<void> markPortionsReceived(List<String> ids) async {
    if (failMark) throw StateError('offline');
    marked.add(ids);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

IntakeEntity _intake(String id) => IntakeEntity(
  id: id,
  unit: 'g',
  amount: 320,
  type: IntakeTypeEntity.dinner,
  meal: MealEntityFixtures.mealOne,
  dateTime: DateTime.utc(2026, 11, 11, 19),
);

PendingPortion _pending(String id, {String? cookId = 'cook'}) => PendingPortion(
  id: id,
  cookId: cookId,
  createdAt: DateTime.utc(2026, 11, 11, 19),
  payload: PortionToServe.encodeIntake(_intake(id)),
);

final _cook = FamilyMemberEntity(
  userId: 'cook',
  displayName: 'Катя',
  role: FamilyRoleEntity.owner,
  joinedAt: DateTime.utc(2026),
);

void main() {
  group('portion payload', () {
    test('survives the trip to another phone', () {
      final intake = _intake('p1');
      final back = _pending('p1').toIntake(servedBy: 'Катя');
      expect(back.id, 'p1');
      expect(back.unit, intake.unit);
      expect(back.amount, 320);
      expect(back.type, IntakeTypeEntity.dinner);
      expect(back.dateTime.toUtc(), intake.dateTime);
      expect(back.meal.name, intake.meal.name);
      expect(
        back.meal.nutriments.energyPerUnit,
        intake.meal.nutriments.energyPerUnit,
      );
      expect(back.servedBy, 'Катя');
    });

    test('drops the photo path, which means nothing on another phone', () {
      final payload = PortionToServe.encodeIntake(_intake('p1'));
      expect((payload['meal'] as Map)['localImagePath'], isNull);
    });

    test('the RPC item carries id, recipient and payload', () {
      final item = PortionToServe(
        id: 'p1',
        recipientId: 'boris',
        intake: _intake('p1'),
      ).toRpcItem();
      expect(item['id'], 'p1');
      expect(item['recipient_id'], 'boris');
      expect((item['payload'] as Map)['amount'], 320);
    });
  });

  group('FamilyPortionService', () {
    late _Families families;
    late List<IntakeEntity> diary;
    late FamilyPortionService service;
    late _Account account;

    setUp(() {
      families = _Families()
        ..family = FamilyEntity(id: 'f', name: 'Т', members: [_cook]);
      diary = [];
      account = _Account(_user('me'));
      service = FamilyPortionService(
        account: account,
        family: families,
        intakeExists: (id) async => diary.any((i) => i.id == id),
        addIntake: (intake) async => diary.add(intake),
      );
    });

    test(
      'adds a waiting portion to the diary, named after the cook, then marks it',
      () async {
        families.pending = [_pending('p1')];

        expect(await service.receivePending(), 1);

        expect(diary.single.id, 'p1');
        expect(diary.single.servedBy, 'Катя');
        expect(families.marked.single, ['p1']);
      },
    );

    test('does nothing when signed out', () async {
      account.currentUser = null;
      families.pending = [_pending('p1')];

      expect(await service.receivePending(), 0);
      expect(diary, isEmpty);
    });

    test('does nothing when no portion is waiting', () async {
      expect(await service.receivePending(), 0);
      expect(families.marked, isEmpty);
    });

    test('a portion read twice is added once', () async {
      families.pending = [_pending('p1')];
      families.failMark = true;
      await expectLater(service.receivePending(), throwsStateError);
      expect(diary, hasLength(1));

      families.failMark = false;
      expect(await service.receivePending(), 0);
      expect(diary, hasLength(1));
      expect(families.marked.single, ['p1']);
    });

    test(
      'a portion from a deleted account still arrives, marked as served',
      () async {
        families.pending = [_pending('p1', cookId: null)];

        expect(await service.receivePending(), 1);
        expect(diary.single.servedBy, '');
      },
    );

    test('an unreadable portion is skipped and left waiting', () async {
      families.pending = [
        PendingPortion(
          id: 'bad',
          cookId: 'cook',
          createdAt: DateTime.utc(2026),
          payload: const {'amount': 'lots'},
        ),
        _pending('p2'),
      ];

      expect(await service.receivePending(), 1);
      expect(diary.single.id, 'p2');
      expect(families.marked.single, ['p2']);
    });
  });
}
