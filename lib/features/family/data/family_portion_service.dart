import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/features/family/data/account_repository.dart';
import 'package:opennutritracker/features/family/data/family_repository.dart';

/// Brings portions a family cook served into this device's diary.
///
/// The mailbox is on the server; the diary is here. A portion is added under
/// the id the cook gave it, so one that is read twice (the "received" mark
/// failed, the app closed half way) is added once. It is marked received only
/// after it is in the diary, so a failure leaves it waiting for the next try.
class FamilyPortionService {
  final _log = Logger('FamilyPortionService');
  final AccountRepository _account;
  final FamilyRepository _family;
  final Future<bool> Function(String intakeId) _intakeExists;
  final Future<void> Function(IntakeEntity intake) _addIntake;

  bool _busy = false;

  FamilyPortionService({
    required AccountRepository account,
    required FamilyRepository family,
    required Future<bool> Function(String intakeId) intakeExists,
    required Future<void> Function(IntakeEntity intake) addIntake,
  }) : _account = account,
       _family = family,
       _intakeExists = intakeExists,
       _addIntake = addIntake;

  /// Adds every waiting portion to the diary. Returns how many were new; 0
  /// when signed out, when a run is already going, or when nothing waits.
  /// Network and server errors are the caller's to ignore: the portions stay
  /// in the mailbox.
  Future<int> receivePending() async {
    final user = _account.currentUser;
    if (user == null || _busy) return 0;
    _busy = true;
    try {
      final pending = await _family.getPendingPortions(user.id);
      if (pending.isEmpty) return 0;

      final family = await _family.getMyFamily();
      final handled = <String>[];
      var added = 0;
      for (final portion in pending) {
        final IntakeEntity intake;
        try {
          final cook = portion.cookId == null
              ? null
              : family?.memberOf(portion.cookId!);
          // An empty name still marks the portion as served; the card then
          // says "a family member".
          intake = portion.toIntake(servedBy: cook?.displayName ?? '');
        } catch (e, st) {
          // Written by a build this one cannot read. Left in the mailbox
          // rather than thrown away, so an update can still deliver it.
          _log.warning('Portion ${portion.id} is unreadable, skipped', e, st);
          continue;
        }
        if (!await _intakeExists(intake.id)) {
          await _addIntake(intake);
          added++;
        }
        handled.add(portion.id);
      }
      if (handled.isNotEmpty) await _family.markPortionsReceived(handled);
      return added;
    } finally {
      _busy = false;
    }
  }
}
