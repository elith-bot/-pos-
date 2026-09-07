class RestockHistoryModel {
  final int id;
  final int productId;
  final int quantity;
  final double purchasePrice;
  final String createdAt;

  RestockHistoryModel({
    required this.id,
    required this.productId,
    required this.quantity,
    required this.purchasePrice,
    required this.createdAt,
  });

  factory RestockHistoryModel.fromJson(Map<String, dynamic> json) {
    return RestockHistoryModel(
      id: json['id'] ?? 0,
      productId: json['product_id'] ?? 0,
      quantity: json['quantity'] ?? 0,
      purchasePrice: (json['purchase_price'] ?? 0.0).toDouble(),
      createdAt: json['created_at'] ?? '',
    );
  }
}
