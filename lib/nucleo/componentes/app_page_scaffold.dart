import 'package:flutter/material.dart';

import 'package:scan_agbc/nucleo/tema/app_theme.dart';

class AppPageScaffold extends StatelessWidget {
  const AppPageScaffold({
    super.key,
    this.title,
    this.appBar,
    required this.body,
    this.bodyPadding,
    this.backgroundDecoration = AppTheme.pageDecoration,
    this.drawer,
    this.floatingActionButton,
    this.safeAreaTop = false,
    this.resizeToAvoidBottomInset,
    this.centerBodyOnLargeScreens = true,
    this.maxBodyWidth = AppTheme.maxPageBodyWidth,
  });

  final String? title;
  final PreferredSizeWidget? appBar;
  final Widget body;
  final EdgeInsetsGeometry? bodyPadding;
  final Decoration backgroundDecoration;
  final Widget? drawer;
  final Widget? floatingActionButton;
  final bool safeAreaTop;
  final bool? resizeToAvoidBottomInset;
  final bool centerBodyOnLargeScreens;
  final double? maxBodyWidth;

  @override
  Widget build(BuildContext context) {
    Widget currentBody = body;
    if (bodyPadding != null) {
      currentBody = Padding(padding: bodyPadding!, child: currentBody);
    }

    if (centerBodyOnLargeScreens && maxBodyWidth != null) {
      final maxWidth = maxBodyWidth!;
      final constrainedBody = currentBody;
      currentBody = LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth <= maxWidth) {
            return constrainedBody;
          }
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: constrainedBody,
            ),
          );
        },
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      drawer: drawer,
      floatingActionButton: floatingActionButton,
      appBar:
          appBar ??
          (title == null
              ? null
              : AppBar(
                  automaticallyImplyLeading: drawer == null,
                  leading: drawer == null
                      ? null
                      : Builder(
                          builder: (context) {
                            return IconButton(
                              tooltip: null,
                              icon: const Icon(Icons.menu_rounded),
                              onPressed: () {
                                Scaffold.of(context).openDrawer();
                              },
                            );
                          },
                        ),
                  title: Text(
                    title!,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                )),
      body: Container(
        decoration: backgroundDecoration,
        child: SafeArea(top: safeAreaTop, bottom: false, child: currentBody),
      ),
    );
  }
}
