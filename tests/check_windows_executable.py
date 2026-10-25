"""Check that the delivered executable opens as a Windows GUI application."""
from pathlib import Path
import struct
import sys

path = Path(sys.argv[1])
data = path.read_bytes()
assert data[:2] == b'MZ', 'Not a Windows executable'
offset = struct.unpack_from('<I', data, 0x3c)[0]
assert data[offset:offset+4] == b'PE\0\0', 'Missing PE header'
subsystem = struct.unpack_from('<H', data, offset+24+68)[0]
print(f'WINDOWS_SUBSYSTEM={subsystem}', flush=True)
assert subsystem == 2, 'Expected Windows GUI subsystem (2); console builds (3) show a terminal at startup'
print('GUI_EXECUTABLE_OK')
