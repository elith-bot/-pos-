class RestockHistoryModel {
  final int id;
  final int productId;
  final double quantity;
  final double purchasePrice;
  final String note;
  final String createdAt;

  RestockHistoryModel({
    required this.id,
    required this.productId,
    required this.quantity,
    required this.purchasePrice,
    required this.note,
    required this.createdAt,
  });

  factory RestockHistoryModel.fromJson(Map<String, dynamic> json) {
    return RestockHistoryModel(
      id: json['id'] ?? 0,
      productId: json['product_id'] ?? 0,
      quantity: (json['quantity'] is num)
          ? (json['quantity'] as num).toDouble()
          : (double.tryParse(json['quantity']?.toString() ?? '0') ?? 0.0),
      purchasePrice: (json['purchase_price'] is num)
          ? (json['purchase_price'] as num).toDouble()
          : (double.tryParse(json['purchase_price']?.toString() ?? '0') ?? 0.0),
      note: json['note'] ?? '',
      createdAt: json['created_at'] ?? '',
    );
  }
}
