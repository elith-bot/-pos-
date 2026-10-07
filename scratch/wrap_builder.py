import re

file_path = r"c:\Users\Mac-x77\Desktop\كاشير\frontend\lib\screens\pos_screen.dart"

with open(file_path, "r", encoding="utf-8") as f:
    text = f.read()

# We need to wrap `return Container(` in `buildCartArea()` with `ValueListenableBuilder`
# Let's find `Widget buildCartArea() {`
idx1 = text.find("Widget buildCartArea() {")
idx2 = text.find("return Container(", idx1)

if idx2 != -1:
    text = text[:idx2] + "return ValueListenableBuilder<List<CartItemModel>>(\n      valueListenable: _cartNotifier,\n      builder: (context, _cart, child) {\n        " + text[idx2:]

    # Now we need to find the end of `buildCartArea` to close the builder.
    # We can do this by counting braces from `Widget buildCartArea() {`
    def find_closing_brace(s, start):
        count = 0
        for i in range(start, len(s)):
            if s[i] == '{':
                count += 1
            elif s[i] == '}':
                count -= 1
                if count == 0:
                    return i
        return -1

    idx3 = find_closing_brace(text, text.find("{", idx1))
    
    # insert `});` before the closing brace of buildCartArea
    # The last thing returned is a Container
    # So we replace the last `);` with `);\n      });`
    
    # Let's just find the last `);` before idx3
    last_semicolon = text.rfind(");", idx1, idx3)
    text = text[:last_semicolon+2] + "\n      });" + text[last_semicolon+2:]

    with open(file_path, "w", encoding="utf-8") as f:
        f.write(text)
    print("Wrapped with ValueListenableBuilder successfully.")
else:
    print("Could not find return Container( in buildCartArea")
