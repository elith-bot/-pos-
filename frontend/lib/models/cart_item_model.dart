import 'product_model.dart';

class CartItemModel {
  final ProductModel product;
  double quantity;
  double unitPurchasePrice;
  double unitSellingPrice;
  double discount; // Can be negative for extra charges/fees

  CartItemModel({
    required this.product,
    this.quantity = 1.0,
    required this.unitPurchasePrice,
    required this.unitSellingPrice,
    this.discount = 0.0,
  });

  // Dynamic calculations
  // Effective unit selling price after discount (if discount is positive -> price decreases, if negative -> price increases)
  double get effectiveUnitPrice => unitSellingPrice - discount;

  // If product is sold by weight, the quantity represents grams, but price is per weightUnitGrams (e.g., 1 Kilo = 1000g).
  double get effectiveQuantity => product.isWeight && product.weightUnitGrams > 0 
      ? quantity / product.weightUnitGrams 
      : quantity;

  // Total price for this cart item line
  double get totalPrice => effectiveUnitPrice * effectiveQuantity;
  set totalPrice(double newTotal) {
    if (effectiveQuantity > 0) {
      discount = unitSellingPrice - (newTotal / effectiveQuantity);
    }
  }

  double get totalPurchaseCost => unitPurchasePrice * effectiveQuantity;
  double get totalSellingAmount => unitSellingPrice * effectiveQuantity;
  double get totalDiscountAmount => discount * effectiveQuantity;
  
  set totalDiscountAmount(double newTotalDiscount) {
    if (effectiveQuantity > 0) {
      discount = newTotalDiscount / effectiveQuantity;
    }
  }

  double get netProfit => totalPrice - totalPurchaseCost;

  Map<String, dynamic> toJson() {
    return {
      'product_id': product.id,
      'product_name': product.name,
      'quantity': quantity,
      'unit_purchase_price': unitPurchasePrice,
      'unit_selling_price': unitSellingPrice,
      'discount': discount,
      'total_price': totalPrice,
      'profit': netProfit,
    };
  }
}
