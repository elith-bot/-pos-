import os

pos_file = r"c:\Users\Mac-x77\Desktop\كاشير\frontend\lib\screens\pos_screen.dart"
with open(pos_file, "r", encoding="utf-8") as f:
    text = f.read()

def get_bracket_content(s, start_idx):
    # start_idx should be the index of the opening bracket '{' or '[' or '('
    open_b = s[start_idx]
    if open_b == '{': close_b = '}'
    elif open_b == '[': close_b = ']'
    elif open_b == '(': close_b = ')'
    else: return -1
    
    count = 1
    idx = start_idx + 1
    while idx < len(s):
        if s[idx] == open_b:
            count += 1
        elif s[idx] == close_b:
            count -= 1
            if count == 0:
                return idx
        idx += 1
    return -1

scaffold_idx = text.find('return Scaffold(')
if scaffold_idx == -1:
    print("Could not find Scaffold")
    exit(1)

pre_scaffold = text[:scaffold_idx]

# Find the Row's children array
row_children_idx = text.find('children: [', scaffold_idx)
if row_children_idx == -1:
    print("Could not find children: [")
    exit(1)

children_open = text.find('[', row_children_idx)
children_close = get_bracket_content(text, children_open)

children_content = text[children_open+1:children_close]

# The children content has two main widgets.
# 1. Expanded( ... )
# 2. Container( ... )

expanded_idx = children_content.find('Expanded(')
expanded_end = get_bracket_content(children_content, expanded_idx + len('Expanded') )

container_idx = children_content.find('Container(', expanded_end)
container_end = get_bracket_content(children_content, container_idx + len('Container') )

prod_area_str = children_content[expanded_idx:expanded_end+1]
cart_area_str = children_content[container_idx:container_end+1]

# Make Cart Area width dynamic if it was fixed
cart_area_str = cart_area_str.replace('width: 410,', 'width: double.infinity,')

# Now construct the new Scaffold
new_scaffold = """
    Widget buildProductsArea() {
      return """ + prod_area_str + """;
    }

    Widget buildCartArea() {
      return """ + cart_area_str + """;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 800) return const SizedBox.shrink();
          return FloatingActionButton.extended(
            backgroundColor: AppColors.primarySolid,
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (ctx) => Directionality(
                  textDirection: TextDirection.rtl,
                  child: FractionallySizedBox(
                    heightFactor: 0.9,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      child: buildCartArea(),
                    ),
                  ),
                ),
              );
            },
            icon: const Icon(Icons.shopping_cart, color: Colors.white),
            label: Text('${_cart.length} منتجات - ${totalFinalAmount.toStringAsFixed(0)} د.ع', 
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          );
        }
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: LayoutBuilder(
          builder: (context, constraints) {
            bool isMobile = constraints.maxWidth < 800;
            if (isMobile) {
               return buildProductsArea();
            } else {
               return Row(
                 children: [
                   Expanded(flex: 75, child: buildProductsArea()),
                   SizedBox(width: 410, child: buildCartArea()),
                 ],
               );
            }
          }
        ),
      ),
    );
"""

# Replace the old scaffold block
scaffold_end = get_bracket_content(text, text.find('(', scaffold_idx))
post_scaffold = text[scaffold_end+1:]

new_text = pre_scaffold + new_scaffold + post_scaffold

with open(pos_file, "w", encoding="utf-8") as f:
    f.write(new_text)

print("Responsive Layout applied successfully!")
