import re

def safe_name(value):
    value = re.sub(r'[<>:"/\\|?*{};\x00-\x1f]', ' ', str(value))
    value = ' '.join(value.split()).strip(' .')[:65].rstrip(' .')
    if value.upper().split('.')[0] in {'CON','PRN','AUX','NUL',*(f'COM{i}' for i in range(10)),*(f'LPT{i}' for i in range(10))}: value = '_' + value
    return value or 'Cashier'

def application_name(manifest):
    return safe_name(manifest.get('vendor_name') or 'moon') + ' - ' + safe_name(manifest['customer']['name'])
