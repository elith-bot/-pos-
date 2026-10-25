import os

screens = [
    'expenses_screen.dart',
    'analytics_screen.dart',
    'employees_screen.dart',
    'settings_screen.dart',
    'auth_screen.dart'
]

dir_path = r'c:\Users\Mac-x77\Desktop\كاشير\frontend\lib\screens'

for s in screens:
    path = os.path.join(dir_path, s)
    with open(path, 'r', encoding='utf-8') as f:
        code = f.read()
    
    if 'theme_service.dart' not in code:
        code = "import '../services/theme_service.dart';\n" + code
        
    if '_onThemeChanged' not in code:
        code = code.replace(
            'void initState() {',
            'void _onThemeChanged() {\n    if (mounted) setState(() {});\n  }\n\n  @override\n  void initState() {\n    ThemeService.themeModeNotifier.addListener(_onThemeChanged);'
        )
        
        if 'void dispose() {' in code:
            code = code.replace(
                'void dispose() {',
                'void dispose() {\n    ThemeService.themeModeNotifier.removeListener(_onThemeChanged);'
            )
        else:
            last_brace = code.rfind('}')
            code = code[:last_brace] + '''  @override
  void dispose() {
    ThemeService.themeModeNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }
}
'''
        with open(path, 'w', encoding='utf-8') as f:
            f.write(code)
        print(f'Updated {s}')
    else:
        print(f'Already has listener: {s}')
