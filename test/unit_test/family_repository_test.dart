import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:opennutritracker/features/family/data/family_repository.dart';
import 'package:opennutritracker/features/family/domain/entity/family_entity.dart';
import 'package:opennutritracker/features/family/domain/family_exception.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Answers each request with the next queued response and records it.
class _ScriptedClient extends http.BaseClient {
  final sent = <http.Request>[];
  final _responses = <(int, Object?)>[];

  void reply(Object? body, {int status = 200}) =>
      _responses.add((status, body));

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sent.add(request as http.Request);
    final (status, body) = _responses.removeAt(0);
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
      request: request,
    );
  }
}

/// What PostgREST sends back for `raise exception '<code>'`.
Map<String, Object?> _raised(String code) => {
  'code': 'P0001',
  'message': code,
  'details': null,
  'hint': null,
};

void main() {
  late _ScriptedClient http_;
  late FamilyRepository repository;

  setUp(() {
    http_ = _ScriptedClient();
    repository = FamilyRepository(
      SupabaseClient('http://backend.invalid', 'test-key', httpClient: http_),
    );
  });

  group('getMyFamily', () {
    test('is null outside a family', () async {
      http_.reply([]);
      expect(await repository.getMyFamily(), isNull);
      expect(http_.sent, hasLength(1));
    });

    test('joins members to their profile names in joining order', () async {
      http_
        ..reply([
          {'id': 'f1', 'name': 'Титовы'},
        ])
        ..reply([
          {
            'user_id': 'u1',
            'role': 'owner',
            'joined_at': '2026-11-01T10:00:00+00:00',
          },
          {
            'user_id': 'u2',
            'role': 'member',
            'joined_at': '2026-11-02T10:00:00+00:00',
          },
        ])
        ..reply([
          {'user_id': 'u2', 'display_name': 'Боря'},
          {'user_id': 'u1', 'display_name': 'Анна'},
        ]);

      final family = await repository.getMyFamily();

      expect(family!.id, 'f1');
      expect(family.name, 'Титовы');
      expect(family.members.map((m) => m.displayName), ['Анна', 'Боря']);
      expect(family.members.first.role, FamilyRoleEntity.owner);
      expect(family.memberOf('u2')!.isOwner, isFalse);
      expect(
        http_.sent[1].url.queryParameters['order'],
        'joined_at.asc.nullslast,user_id.asc.nullslast',
      );
    });
  });

  group('RPCs', () {
    test('joinFamily posts the code to join_family', () async {
      http_.reply('f1');
      expect(await repository.joinFamily('K7QM2XPA'), 'f1');

      final request = http_.sent.single;
      expect(request.method, 'POST');
      expect(request.url.path, endsWith('/rpc/join_family'));
      expect(jsonDecode(request.body), {'p_code': 'K7QM2XPA'});
    });

    test('createInvite reads the returned row', () async {
      http_.reply([
        {'code': 'K7QM2XPA', 'expires_at': '2026-11-08T12:00:00+00:00'},
      ]);
      final invite = await repository.createInvite();
      expect(invite.code, 'K7QM2XPA');
      expect(invite.expiresAt, DateTime.utc(2026, 11, 8, 12));
      expect(http_.sent.single.url.path, endsWith('/rpc/create_invite'));
    });

    test('removeMember and transferOwnership name the user', () async {
      http_
        ..reply(null, status: 204)
        ..reply(null, status: 204);
      await repository.removeMember('u2');
      await repository.transferOwnership('u3');
      expect(jsonDecode(http_.sent[0].body), {'p_user_id': 'u2'});
      expect(http_.sent[0].url.path, endsWith('/rpc/remove_member'));
      expect(jsonDecode(http_.sent[1].body), {'p_user_id': 'u3'});
      expect(http_.sent[1].url.path, endsWith('/rpc/transfer_ownership'));
    });
  });

  group('errors', () {
    for (final error in FamilyError.values.where(
      (e) => e != FamilyError.unknown,
    )) {
      test('maps ${error.code}', () async {
        http_.reply(_raised(error.code), status: 400);
        await expectLater(
          repository.joinFamily('K7QM2XPA'),
          throwsA(
            isA<FamilyException>().having((e) => e.error, 'error', error),
          ),
        );
      });
    }

    test('an unknown database error is unknown', () async {
      http_.reply(_raised('something_new'), status: 400);
      await expectLater(
        repository.leaveFamily(),
        throwsA(
          isA<FamilyException>().having(
            (e) => e.error,
            'error',
            FamilyError.unknown,
          ),
        ),
      );
    });

    test('a member renaming the family is notOwner', () async {
      // RLS filters the update down to no rows rather than refusing it.
      http_.reply([]);
      await expectLater(
        repository.renameFamily('f1', 'Новое имя'),
        throwsA(
          isA<FamilyException>().having(
            (e) => e.error,
            'error',
            FamilyError.notOwner,
          ),
        ),
      );
    });

    test('a blank family name never reaches the server', () async {
      await expectLater(
        repository.renameFamily('f1', '   '),
        throwsA(
          isA<FamilyException>().having(
            (e) => e.error,
            'error',
            FamilyError.invalidName,
          ),
        ),
      );
      expect(http_.sent, isEmpty);
    });
  });
}
