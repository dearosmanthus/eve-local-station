"""Archive resolved Cargo dependency licenses for this exact lockfile.

Development-only command; no network operations except Cargo metadata may fetch
missing sources. This includes build dependencies as well as runtime crates.
"""
import json
from pathlib import Path
import shutil
import subprocess
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def main():
    result = subprocess.run(['cargo', 'metadata', '--manifest-path', str(ROOT / 'native/Cargo.toml'),
                             '--format-version', '1', '--locked'], check=True, capture_output=True, text=True, encoding='utf-8')
    metadata = json.loads(result.stdout)
    destination = ROOT / 'licenses/cargo'
    destination.mkdir(parents=True, exist_ok=True)
    entries = []
    for package in sorted(metadata['packages'], key=lambda p: (p['name'], p['version'])):
        directory = Path(package['manifest_path']).parent
        archived = []
        for source in directory.iterdir():
            if source.is_file() and (source.name.upper().startswith(('LICENSE', 'LICENCE', 'COPYING', 'NOTICE')) or source.name == package.get('license_file')):
                target = destination / f"{package['name']}-{package['version']}" / source.name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, target)
                archived.append(str(target.relative_to(ROOT)).replace('\\', '/'))
        entries.append({'name': package['name'], 'version': package['version'],
                        'license': package.get('license'), 'source': package.get('source'),
                        'repository': package.get('repository'), 'files': archived})
    (destination / 'inventory.json').write_text(json.dumps(entries, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'Archived {len(entries)} resolved Cargo packages; includes development/build dependencies.')
    config_path = ROOT / 'app/.dart_tool/package_config.json'
    if config_path.is_file():
        dart_entries = []
        for package in json.loads(config_path.read_text(encoding='utf-8'))['packages']:
            uri = package['rootUri']
            if uri.startswith('file:'):
                directory = Path(urllib.request.url2pathname(urllib.parse.urlparse(uri).path))
            else:
                directory = (config_path.parent / uri).resolve()
            archived = []
            for source in directory.iterdir():
                if source.is_file() and source.name.upper().startswith(('LICENSE', 'LICENCE', 'COPYING', 'NOTICE')):
                    target = ROOT / 'licenses/dart' / package['name'] / source.name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(source, target)
                    archived.append(str(target.relative_to(ROOT)).replace('\\', '/'))
            dart_entries.append({'name': package['name'], 'files': archived})
        destination = ROOT / 'licenses/dart'
        destination.mkdir(parents=True, exist_ok=True)
        (destination / 'inventory.json').write_text(json.dumps(dart_entries, indent=2) + '\n', encoding='utf-8')
        print(f'Archived {len(dart_entries)} resolved Dart package entries.')
    # Rust libraries do not automatically enter Flutter's generated NOTICES.
    # Add the audited archive as a local asset for the app's license page.
    notices = [
        'EVE Local Station — third-party notices',
        'Original code is MIT. Third-party software and CCP game data retain their own rights.',
        'Copyright © 2014 CCP hf. All rights reserved. "EVE", "EVE Online", "CCP", and all related logos and images are trademarks or registered trademarks of CCP hf.',
        'Independent fan tool. Not endorsed or sponsored by CCP. Official data terms: https://developers.eveonline.com/license-agreement',
        'Flutter/Dart notices are also provided by Flutter in this license view.',
    ]
    notice_files = [ROOT / 'LICENSE', ROOT / 'licenses/eve-fit-os-MIT.txt', ROOT / 'licenses/eve-fit-os-APACHE-2.0.txt']
    notice_files += sorted(p for p in (ROOT / 'licenses/cargo').rglob('*') if p.is_file() and p.name != 'inventory.json')
    for source in notice_files:
        notices += ['\n' + '=' * 72, str(source.relative_to(ROOT)).replace('\\', '/'), source.read_text(encoding='utf-8', errors='replace')]
    asset = ROOT / 'app/assets/licenses/THIRD_PARTY_NOTICES.txt'
    asset.parent.mkdir(parents=True, exist_ok=True)
    asset.write_text('\n\n'.join(notices) + '\n', encoding='utf-8')
    print('Generated local in-app license asset.')


if __name__ == '__main__':
    main()
