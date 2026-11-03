import 'package:flutter/material.dart';

class BusinessField {
  const BusinessField(
    this.name,
    this.label, {
    this.kind = 'text',
    this.options,
    this.required = true,
  });
  final String name, label, kind;
  final Map<String, String>? options;
  final bool required;
}

Future<bool?> businessForm(
  BuildContext context, {
  required String title,
  required List<BusinessField> fields,
  Map<String, dynamic> initial = const {},
  String? description,
  required Future<void> Function(Map<String, dynamic>) save,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _BusinessForm(
    title: title,
    fields: fields,
    initial: initial,
    description: description,
    save: save,
  ),
);

class _BusinessForm extends StatefulWidget {
  const _BusinessForm({
    required this.title,
    required this.fields,
    required this.initial,
    required this.save,
    this.description,
  });
  final String title;
  final List<BusinessField> fields;
  final Map<String, dynamic> initial;
  final String? description;
  final Future<void> Function(Map<String, dynamic>) save;
  @override
  State<_BusinessForm> createState() => _BusinessFormState();
}

class _BusinessFormState extends State<_BusinessForm> {
  final form = GlobalKey<FormState>();
  late final controllers = {
    for (final f in widget.fields)
      f.name: TextEditingController(
        text: '${widget.initial[f.name] ?? f.options?.keys.first ?? ''}',
      ),
  };
  bool busy = false;
  String? error;
  double? number(String text) {
    for (var i = 0; i < 10; i++) {
      text = text
          .replaceAll('٠١٢٣٤٥٦٧٨٩'[i], '$i')
          .replaceAll('۰۱۲۳۴۵۶۷۸۹'[i], '$i');
    }
    return double.tryParse(text.replaceAll('٫', '.').trim());
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.save({
        for (final f in widget.fields)
          f.name: f.kind == 'number'
              ? number(controllers[f.name]!.text)
              : controllers[f.name]!.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        setState(() {
          error = e.toString().replaceFirst('Exception: ', '');
          busy = false;
        });
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.description != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(widget.description!),
                    ),
                  for (final f in widget.fields)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: f.options != null
                          ? DropdownButtonFormField<String>(
                              initialValue: controllers[f.name]!.text,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: f.label,
                                border: const OutlineInputBorder(),
                              ),
                              items: f.options!.entries
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e.key,
                                      child: Text(e.value),
                                    ),
                                  )
                                  .toList(),
                              onChanged: busy
                                  ? null
                                  : (value) =>
                                        controllers[f.name]!.text = value!,
                            )
                          : TextFormField(
                              controller: controllers[f.name],
                              enabled: !busy,
                              keyboardType: f.kind == 'number'
                                  ? const TextInputType.numberWithOptions(
                                      decimal: true,
                                    )
                                  : TextInputType.text,
                              minLines: f.kind == 'notes' ? 3 : 1,
                              maxLines: f.kind == 'notes' ? 5 : 1,
                              decoration: InputDecoration(
                                labelText: f.label,
                                border: const OutlineInputBorder(),
                                suffixIcon: f.kind == 'date'
                                    ? IconButton(
                                        icon: const Icon(Icons.calendar_month),
                                        onPressed: busy
                                            ? null
                                            : () async {
                                                final picked =
                                                    await showDatePicker(
                                                      context: context,
                                                      initialDate:
                                                          DateTime.tryParse(
                                                            controllers[f.name]!
                                                                .text,
                                                          ) ??
                                                          DateTime.now(),
                                                      firstDate: DateTime(1950),
                                                      lastDate: DateTime(2100),
                                                    );
                                                if (picked != null)
                                                  controllers[f.name]!.text =
                                                      picked
                                                          .toIso8601String()
                                                          .substring(0, 10);
                                              },
                                      )
                                    : null,
                              ),
                              validator: (value) {
                                if (f.required && (value ?? '').trim().isEmpty)
                                  return 'الحقل مطلوب';
                                if (f.kind == 'number') {
                                  final n = number(value ?? '');
                                  if (n == null || !n.isFinite || n < 0)
                                    return 'أدخل مبلغاً أو عدداً غير سالب';
                                }
                                if (f.kind == 'date' &&
                                    DateTime.tryParse(value ?? '') == null)
                                  return 'التاريخ بصيغة YYYY-MM-DD';
                                return null;
                              },
                            ),
                    ),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: busy ? null : submit,
            child: Text(busy ? 'جارٍ الحفظ…' : 'حفظ'),
          ),
        ],
      ),
    ),
  );
}
