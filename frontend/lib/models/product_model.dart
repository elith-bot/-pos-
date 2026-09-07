class ProductModel {
  final int id;
  final String name;
  final String imageUrl;
  final double purchasePrice;
  final double sellingPrice;
  final double unitProfit;
  final double stockQuantity;
  final String category;
  final String barcode;
  final bool isWeight;
  final int weightUnitGrams;
  final double weightIncrementStep;
  final String createdAt;

  ProductModel({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.purchasePrice,
    required this.sellingPrice,
    required this.unitProfit,
    required this.stockQuantity,
    required this.category,
    required this.barcode,
    required this.isWeight,
    required this.weightUnitGrams,
    required this.weightIncrementStep,
    required this.createdAt,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      imageUrl: json['image_url'] ?? '',
      purchasePrice: (json['purchase_price'] ?? 0.0).toDouble(),
      sellingPrice: (json['selling_price'] ?? 0.0).toDouble(),
      unitProfit: (json['unit_profit'] ?? 0.0).toDouble(),
      stockQuantity: (json['stock_quantity'] ?? 0).toDouble(),
      category: json['category'] ?? 'عام',
      barcode: json['barcode'] ?? '',
      isWeight: json['is_weight'] ?? false,
      weightUnitGrams: json['weight_unit_grams'] ?? 1000,
      weightIncrementStep: (json['weight_increment_step'] ?? 100.0).toDouble(),
      createdAt: json['created_at'] ?? '',
    );
  }
}
