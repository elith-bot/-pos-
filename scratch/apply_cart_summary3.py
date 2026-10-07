import re

file_path = r"c:\Users\Mac-x77\Desktop\كاشير\frontend\lib\screens\pos_screen.dart"

with open(file_path, "r", encoding="utf-8") as f:
    text = f.read()

start_summary = text.find("// 1. Total Purchase Cost (Fixed)")
if start_summary != -1:
    end_summary = text.find("SizedBox(\n                          width: double.infinity,\n                          height: 46,\n                          child: ElevatedButton.icon(", start_summary)
    
    if end_summary != -1:
        replacement = """CartSummaryWidget(
                          totalCostSum: totalCostSum,
                          totalSellingSum: totalSellingSum,
                          totalDiscountSum: totalDiscountSum,
                          totalFinalAmount: totalFinalAmount,
                          totalNetProfitSum: totalNetProfitSum,
                          totalItems: _cart.length,
                          canViewPurchasePrice: appPermissions.canViewPurchasePrice,
                          canViewProfit: appPermissions.canViewProfit,
                          onUpdateTotalSelling: (newTotal) {
                            if (totalSellingSum > 0) {
                              double ratio = newTotal / totalSellingSum;
                              setState(() {
                                for (var i in _cart) { i.unitSellingPrice *= ratio; }
                              });
                            }
                          },
                          onUpdateTotalDiscount: (newDisc) {
                            setState(() {
                              _updateCartTotalDiscount(newDisc);
                            });
                          },
                          onUpdateFinalTotal: (newFinal) {
                            setState(() {
                              _updateCartFinalTotal(newFinal);
                            });
                          },
                        ),
                        const SizedBox(height: 8),

                        """
        text = text[:start_summary] + replacement + text[end_summary:]

        with open(file_path, "w", encoding="utf-8") as f:
            f.write(text)
        print("Successfully replaced summary fields!")
    else:
        print("Could not find the end of the summary fields.")
else:
    print("Could not find the start of the summary fields.")
