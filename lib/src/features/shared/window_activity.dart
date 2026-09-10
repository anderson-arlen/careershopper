import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Observes input across the window, including navigation and modal routes.
class WindowActivity extends StatefulWidget {
  const WindowActivity({required this.child, super.key});
  final Widget child;

  static Listenable? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ActivityScope>()?.activity;

  @override
  State<WindowActivity> createState() => _WindowActivityState();
}

class _WindowActivityState extends State<WindowActivity>
    with WidgetsBindingObserver {
  final _activity = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_key);
    WidgetsBinding.instance.addObserver(this);
  }

  bool _key(KeyEvent event) {
    _activity.value++;
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _activity.value++;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_key);
    WidgetsBinding.instance.removeObserver(this);
    _activity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ActivityScope(
    activity: _activity,
    child: Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _activity.value++,
      onPointerUp: (_) => _activity.value++,
      onPointerMove: (_) => _activity.value++,
      onPointerSignal: (_) => _activity.value++,
      child: MouseRegion(
        onHover: (_) => _activity.value++,
        child: widget.child,
      ),
    ),
  );
}

class _ActivityScope extends InheritedWidget {
  const _ActivityScope({required this.activity, required super.child});
  final Listenable activity;

  @override
  bool updateShouldNotify(_ActivityScope oldWidget) =>
      oldWidget.activity != activity;
}
