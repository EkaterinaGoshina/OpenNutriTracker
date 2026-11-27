import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/user_image.dart';
import 'package:opennutritracker/core/domain/entity/profile_entity.dart';

/// Round avatar for a profile: shows the profile picture when one is set,
/// otherwise the first letter of the name, falling back to a person icon
/// for an unnamed profile.
class ProfileAvatar extends StatelessWidget {
  final ProfileEntity profile;
  final double radius;

  const ProfileAvatar({super.key, required this.profile, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imagePath = profile.imagePath;

    final initial = CircleAvatar(
      radius: radius,
      backgroundColor: theme.colorScheme.primaryContainer,
      foregroundColor: theme.colorScheme.onPrimaryContainer,
      child: profile.name.trim().isEmpty
          ? Icon(Icons.person_outline, size: radius)
          : Text(
              profile.name.trim().characters.first.toUpperCase(),
              style: TextStyle(fontSize: radius * 0.9),
            ),
    );
    if (imagePath == null) return initial;
    return ClipOval(
      child: UserImage(
        relativePath: imagePath,
        width: radius * 2,
        height: radius * 2,
        fallback: initial,
      ),
    );
  }
}
