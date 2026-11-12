import 'package:flutter/material.dart';

/// One confirmation selects both the local calendar date and 24-hour time.
Future<DateTime?> pickReportDateTime(
  BuildContext context, {
  required DateTime initial,
  required String title,
}) => showDialog<DateTime>(
  context: context,
  builder: (_) => _DateTimeDialog(initial: initial, title: title),
);

class _DateTimeDialog extends StatefulWidget {
  const _DateTimeDialog({required this.initial, required this.title});
  final DateTime initial;
  final String title;
  @override
  State<_DateTimeDialog> createState() => _DateTimeDialogState();
}

class _DateTimeDialogState extends State<_DateTimeDialog> {
  late DateTime day = widget.initial;
  late int hour = widget.initial.hour, minute = widget.initial.minute;
  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('اختر التاريخ والوقت المحلي (24 ساعة)'),
              CalendarDatePicker(
                initialDate: day,
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
                onDateChanged: (value) => setState(() => day = value),
              ),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      key: const ValueKey('report-hour'),
                      initialValue: hour,
                      decoration: const InputDecoration(
                        labelText: 'الساعة',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (var h = 0; h < 24; h++)
                          DropdownMenuItem(
                            value: h,
                            child: Text(h.toString().padLeft(2, '0')),
                          ),
                      ],
                      onChanged: (h) => setState(() => hour = h!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      key: const ValueKey('report-minute'),
                      initialValue: minute,
                      decoration: const InputDecoration(
                        labelText: 'الدقيقة',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (var m = 0; m < 60; m++)
                          DropdownMenuItem(
                            value: m,
                            child: Text(m.toString().padLeft(2, '0')),
                          ),
                      ],
                      onChanged: (m) => setState(() => minute = m!),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const ValueKey('apply-report-datetime'),
          onPressed: () => Navigator.pop(
            context,
            DateTime(day.year, day.month, day.day, hour, minute),
          ),
          child: const Text('تطبيق التاريخ والوقت'),
        ),
      ],
    ),
  );
}
