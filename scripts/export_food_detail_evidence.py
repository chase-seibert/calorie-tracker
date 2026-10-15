#!/usr/bin/env python3
"""Export the complete #196 simulator matrix without altering screenshot pixels."""
import argparse
import base64
import hashlib
import html
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

REQUIRED = {
    'usda-portioned-log', 'usda-weight-log', 'off-packaged-log',
    'yum-chase-configured-log', 'custom-food-log', 'saved-meal-log',
    'imported-meal-review', 'photo-meal-review', 'one-off-meal-edit',
    'yum-chase-configured-log-scrolled', 'saved-meal-log-scrolled',
    'imported-meal-review-scrolled', 'photo-meal-review-scrolled',
    'usda-portioned-edit', 'off-packaged-edit', 'yum-chase-configured-edit',
    'saved-meal-edit', 'usda-unit-menu', 'yum-chase-configured-child',
}
OPTIONAL = {'imported-meal-review-child', 'photo-meal-review-child'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('result_bundle', type=Path)
    parser.add_argument('--output', type=Path, default=Path('docs/evidence/task-196/unified-ui'))
    args = parser.parse_args()
    result = args.result_bundle.resolve(strict=True)
    with tempfile.TemporaryDirectory(prefix='task196-evidence-') as temp:
        root = Path(temp)
        subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result),
                        '--output-path', str(root)], check=True, stdout=subprocess.DEVNULL)
        captures = {}
        for test in json.loads((root / 'manifest.json').read_text()):
            if not test['testIdentifier'].endswith('testMixedCatalogCustomizationAndScreenshotMatrix()'):
                continue
            for attachment in test['attachments']:
                name = attachment['suggestedHumanReadableName'].split('_0_')[0]
                if name in REQUIRED | OPTIONAL and attachment['exportedFileName'].endswith('.png'):
                    captures[name] = attachment
        missing = REQUIRED - captures.keys()
        if missing:
            raise SystemExit('Incomplete capture matrix: ' + ', '.join(sorted(missing)))
        sizes = set()
        manifest = {}
        for name, attachment in captures.items():
            data = (root / attachment['exportedFileName']).read_bytes()
            if data[:8] != b'\x89PNG\r\n\x1a\n':
                raise SystemExit(f'Invalid PNG: {name}')
            width, height = struct.unpack('>II', data[16:24])
            sizes.add((width, height))
            manifest[name + '.png'] = {
                'sha256': hashlib.sha256(data).hexdigest(), 'width': width, 'height': height,
                'device_id': attachment['deviceId'], 'device_name': attachment['deviceName'],
                'timestamp': attachment.get('timestamp'),
                'original_attachment': attachment['exportedFileName'],
            }
        if len(sizes) != 1:
            raise SystemExit(f'Inconsistent screenshot viewports: {sizes}')
        args.output.mkdir(parents=True, exist_ok=True)
        for name, attachment in captures.items():
            shutil.copyfile(root / attachment['exportedFileName'], args.output / (name + '.png'))
        (args.output / 'capture-manifest.json').write_text(json.dumps({
            'result_bundle': str(result), 'captures': manifest}, indent=2) + '\n')
        cards = []
        for title, filename in [('USDA', 'usda-portioned-log.png'), ('OFF', 'off-packaged-log.png'),
                                ('Chase Food', 'yum-chase-configured-log.png'), ('Saved meal', 'saved-meal-log.png')]:
            encoded = base64.b64encode((args.output / filename).read_bytes()).decode('ascii')
            cards.append(f'<figure><figcaption>{html.escape(title)}</figcaption>'
                         f'<a href="{filename}"><img src="data:image/png;base64,{encoded}" '
                         f'alt="{html.escape(title)} customization screen"></a></figure>')
        document = '''<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Task 196 — unified customization comparison</title>
<style>body{margin:0;padding:24px;background:#faf7f2;font:16px system-ui;color:#222}
h1{font-size:24px;margin:0 0 8px}p{color:#666}main{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:16px}
figure{margin:0}figcaption{font-weight:650;padding:12px 0}img{display:block;width:100%;height:auto;border:1px solid #ddd;border-radius:8px}
@media(max-width:900px){main{grid-template-columns:repeat(2,minmax(0,1fr))}}
@media(max-width:500px){main{grid-template-columns:1fr}}
</style><h1>One customization layout</h1><p>Actual iPhone 17 Pro / iOS 27 simulator captures. Tap an image for its unaltered PNG.</p><main>'''
        (args.output / 'comparison.html').write_text(document + ''.join(cards) + '</main></html>\n')
        print(f'Exported {len(captures)} unaltered screenshots, manifest and comparison to {args.output}.')


if __name__ == '__main__':
    main()
