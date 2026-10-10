"""Embed synthetic JPEGs solely in integration tests, never the production app."""
from pathlib import Path
import base64
root = Path(__file__).resolve().parent.parent
output = root / 'mobile/integration_test/demo_fixtures.dart'
with output.open('w') as file:
    file.write("// Generated from demo/assets. Synthetic identities only.\nimport 'dart:convert';\nimport 'dart:typed_data';\n\n")
    for name in ['document', 'selfie']:
        encoded = base64.b64encode((root / f'demo/assets/{name}.jpg').read_bytes()).decode()
        file.write(f"Uint8List get {name}Fixture => base64Decode(\n")
        for start in range(0, len(encoded), 100):
            file.write(f"  '{encoded[start:start+100]}'\n")
        file.write(');\n\n')
