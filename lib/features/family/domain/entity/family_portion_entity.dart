import 'dart:convert';

import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';

/// One portion a cook serves to a family member: what goes into that
/// member's diary, and the id both phones know it by.
///
/// [id] is also the id of the intake the member's phone creates, so a portion
/// that is read twice is added once.
class PortionToServe {
  final String id;
  final String recipientId;
  final IntakeEntity intake;

  const PortionToServe({
    required this.id,
    required this.recipientId,
    required this.intake,
  });

  /// The row's `payload`: the meal as a diary stores it, plus unit, amount,
  /// meal type and time. A photo path is dropped, it means nothing on another
  /// phone.
  static Map<String, dynamic> encodeIntake(IntakeEntity intake) {
    // Through JSON so nested objects become plain maps, as they will be when
    // the other phone reads them back.
    final meal = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(MealDBO.fromMealEntity(intake.meal).toJson()))
          as Map,
    )..['localImagePath'] = null;
    return {
      'unit': intake.unit,
      'amount': intake.amount,
      'type': intake.type.name,
      'dateTime': intake.dateTime.toUtc().toIso8601String(),
      'meal': meal,
    };
  }

  /// The `serve_portions` item for this portion.
  Map<String, dynamic> toRpcItem() => {
    'id': id,
    'recipient_id': recipientId,
    'payload': encodeIntake(intake),
  };
}

/// A portion waiting in the caller's mailbox.
class PendingPortion {
  final String id;

  /// Null when the cook's account was deleted after serving.
  final String? cookId;
  final DateTime createdAt;
  final Map<String, dynamic> payload;

  const PendingPortion({
    required this.id,
    required this.cookId,
    required this.createdAt,
    required this.payload,
  });

  /// The diary entry this portion becomes, marked as served by
  /// [servedBy]. Throws when the payload is not one a current build wrote,
  /// which the caller treats as a portion to skip rather than a crash.
  IntakeEntity toIntake({String? servedBy}) {
    final meal = MealEntity.fromMealDBO(
      MealDBO.fromJson(Map<String, dynamic>.from(payload['meal'] as Map)),
    );
    return IntakeEntity(
      id: id,
      unit: payload['unit'] as String,
      amount: (payload['amount'] as num).toDouble(),
      type: IntakeTypeEntity.values.byName(payload['type'] as String),
      meal: meal,
      dateTime: DateTime.parse(payload['dateTime'] as String).toLocal(),
      servedBy: servedBy,
    );
  }
}
