import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/models.dart';
import 'calendar_schedule.dart';

/// Data and commands for the shared month UI. Gesture and layout logic stay in
/// CalendarContent/CalendarInteractionSurface, regardless of the record type.
abstract class CalendarDataSource {
  const CalendarDataSource();
  int get firstYear => 2000;
  int get lastYear => 9999;
  AutoDisposeFutureProvider<PageResult> monthProvider(DateTime month);
  void invalidateMonth(WidgetRef ref, DateTime month);
  void refresh(WidgetRef ref);
  Future<Record> detail(WidgetRef ref, String id);
  Future<void> saveMove(WidgetRef ref, Record record, CalendarSchedule after);
  Future<void> create(BuildContext context, WidgetRef ref, DateTime day);
  Future<void> open(BuildContext context, WidgetRef ref, Record record);
}
