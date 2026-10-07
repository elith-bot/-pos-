import re

file_path = r"c:\Users\Mac-x77\Desktop\كاشير\frontend\lib\screens\pos_screen.dart"

with open(file_path, "r", encoding="utf-8") as f:
    text = f.read()

text = text.replace("createdAt: DateTime.now()", "createdAt: DateTime.now().toIso8601String()")

# Find return GestureDetector(
# and fix the missing ) at the end of the Container.
chunk = """                                      ],
                                    ),
                                  );
                                      },
                                    );
                                  },
                                ),"""

fixed_chunk = """                                      ],
                                    ),
                                  ));
                                      },
                                    );
                                  },
                                ),"""
                                
text = text.replace(chunk, fixed_chunk)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(text)

print("Fixed!")
