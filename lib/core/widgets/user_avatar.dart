import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';

class UserAvatar extends StatelessWidget {
  final double radius;
  final bool showEditButton;
  final VoidCallback? onTap;

  const UserAvatar({
    super.key,
    this.radius = 20,
    this.showEditButton = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appState = context.watch<AppState>();

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          CircleAvatar(
            radius: radius,
            backgroundColor: colorScheme.primary.withOpacity(0.2),
            backgroundImage:
                appState.userImagePath != null
                    ? FileImage(File(appState.userImagePath!))
                    : null,
            child:
                appState.userImagePath == null
                    ? Icon(
                      Icons.person_rounded,
                      size: radius * 1.2,
                      color: colorScheme.primary,
                    )
                    : null,
          ),
          if (showEditButton)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.camera_alt,
                  size: radius * 0.4,
                  color: colorScheme.onPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
