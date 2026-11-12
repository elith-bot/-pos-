"""Read stable system identifiers locally; never transmit raw serial numbers."""
import json
import platform
import subprocess
from pathlib import Path
from license_protocol import LicenseError, fingerprint_digest


def hardware_fingerprint():
    if platform.system() == 'Windows':
        # Fixed commands only. No customer input is interpolated into PowerShell.
        command = "$ErrorActionPreference='Stop'; @{uuid=(Get-CimInstance Win32_ComputerSystemProduct).UUID; board=(Get-CimInstance Win32_BaseBoard | Select-Object -First 1).SerialNumber} | ConvertTo-Json -Compress"
        try:
            result = subprocess.run(['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', command],
                                    capture_output=True, text=True, timeout=20, check=True,
                                    creationflags=subprocess.CREATE_NO_WINDOW)
            values = json.loads(result.stdout)
            invalid = {'', 'none', 'default string', 'to be filled by o.e.m.', 'unknown', 'system serial number',
                       '00000000-0000-0000-0000-000000000000', 'ffffffff-ffff-ffff-ffff-ffffffffffff'}
            values = {k: str(v).strip().lower() for k, v in values.items() if v is not None and str(v).strip().lower() not in invalid}
            if 'uuid' not in values:
                raise ValueError('Missing unique system UUID')
            return fingerprint_digest({'os': 'windows', **values})
        except (subprocess.SubprocessError, OSError, ValueError) as error:
            raise LicenseError('تعذر قراءة بصمة الجهاز. شغّل البرنامج بصلاحيات المسؤول أو تواصل مع الدعم.') from error
    if platform.system() == 'Linux':
        try:
            value = Path('/etc/machine-id').read_text().strip()
            if len(value) != 32 or any(c not in '0123456789abcdef' for c in value):
                raise ValueError()
            return fingerprint_digest({'os': 'linux', 'machine_id': value})
        except (OSError, ValueError) as error:
            raise LicenseError('تعذر قراءة هوية نظام لينكس.') from error
    raise LicenseError('التفعيل يدعم جهاز خادم الكاشير على ويندوز أو لينكس.')
