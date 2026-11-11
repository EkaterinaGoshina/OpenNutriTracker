import 'package:flutter/material.dart';

/// The home tab has no title or logo: a zero-height [AppBar] only reserves the
/// status-bar / notch inset so the content starts below it.
class HomeAppbar extends StatelessWidget implements PreferredSizeWidget {
  const HomeAppbar({super.key});

  @override
  Widget build(BuildContext context) => AppBar(toolbarHeight: 0);

  @override
  Size get preferredSize => Size.zero;
}
