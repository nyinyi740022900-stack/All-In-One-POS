import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'operating_mode_providers.dart';

/// Keeps [localCalendarDayProvider] on today's date for as long as the app
/// is running: a 30-second check (cheap, and it survives a device clock
/// change, which a one-shot midnight timer would not) plus an immediate
/// check whenever the app returns to the foreground.
class CalendarDayTicker extends ConsumerStatefulWidget {
  const CalendarDayTicker({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<CalendarDayTicker> createState() => _CalendarDayTickerState();
}

class _CalendarDayTickerState extends ConsumerState<CalendarDayTicker> {
  Timer? _timer;
  AppLifecycleListener? _lifecycle;

  void _refresh() => ref.read(localCalendarDayProvider.notifier).refresh();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
    _lifecycle = AppLifecycleListener(onResume: _refresh);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
