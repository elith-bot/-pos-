class ExpenseModel {
  final int id;
  final String title;
  final double amount;
  final String category;
  final String notes;
  final String createdBy;
  final DateTime? createdAt;
  final String source;
  bool get editable => source == 'manual' && category != 'مشتريات/بضاعة';

  const ExpenseModel({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.notes,
    required this.createdBy,
    required this.createdAt,
    this.source = 'manual',
  });

  factory ExpenseModel.fromJson(Map<String, dynamic> json) {
    final rawDate = (json['created_at'] ?? '').toString().replaceFirst(
      ' ',
      'T',
    );
    // The API serializes UTC timestamps without a timezone suffix.
    final hasZone = RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(rawDate);
    final date = DateTime.tryParse(hasZone ? rawDate : '${rawDate}Z');
    final category = (json['category'] ?? '').toString().trim();
    return ExpenseModel(
      id: (json['id'] as num).toInt(),
      title: (json['title'] ?? '').toString(),
      amount: (json['amount'] as num).toDouble(),
      category: category.isEmpty ? 'عام' : category,
      notes: (json['notes'] ?? '').toString(),
      createdBy: (json['created_by'] ?? 'غير محدد').toString(),
      createdAt: date?.toLocal(),
      source: json['source']?.toString() ?? 'manual',
    );
  }

  bool matches({
    String query = '',
    String? category,
    DateTime? start,
    DateTime? endExclusive,
  }) {
    if (category != null && this.category != category) return false;
    if (query.trim().isNotEmpty &&
        !'$id $title ${this.category} $notes $createdBy'.toLowerCase().contains(
          query.trim().toLowerCase(),
        )) {
      return false;
    }
    if (start != null || endExclusive != null) {
      final date = createdAt;
      if (date == null) return false;
      if (start != null && date.isBefore(start)) return false;
      if (endExclusive != null && !date.isBefore(endExclusive)) return false;
    }
    return true;
  }
}

double? parseExpenseAmount(String input) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  var value = input.trim();
  for (var i = 0; i < 10; i++) {
    value = value.replaceAll(arabic[i], '$i').replaceAll(persian[i], '$i');
  }
  // Allow grouped numbers, but reject malformed grouping instead of changing it.
  value = value.replaceAll('٫', '.').replaceAll('٬', ',');
  if (!RegExp(r'^(\d+|\d{1,3}(,\d{3})+)(\.\d{1,2})?$').hasMatch(value)) {
    return null;
  }
  final amount = double.tryParse(value.replaceAll(',', ''));
  return amount != null && amount.isFinite && amount > 0 ? amount : null;
}

String expenseMoney(double amount) {
  final parts = amount.toStringAsFixed(2).split('.');
  final grouped = parts.first.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]},',
  );
  return '${parts[1] == '00' ? grouped : '$grouped.${parts[1]}'} د.ع';
}
