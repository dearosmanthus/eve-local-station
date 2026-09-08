"""Package portable source and bundled data, excluding local tools and caches."""
import argparse
import hashlib
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EXCLUDE_DIRS = {'.git', '.dart_tool', '.gradle', '.cxx', '.kotlin', 'build', 'target',
                '__pycache__', 'jniLibs', 'work', 'outputs', '.idea', '.vscode'}
EXCLUDE_NAMES = {'local.properties', 'key.properties', '.flutter-plugins',
                 '.flutter-plugins-dependencies'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('Output exists; choose a new archive path')
    files = [p for p in ROOT.rglob('*') if p.is_file()
             and not (set(p.relative_to(ROOT).parts) & EXCLUDE_DIRS)
             and p.name not in EXCLUDE_NAMES and p.suffix not in {'.jks', '.keystore', '.pyc', '.apk'}]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.output, 'x', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(files):
            archive.write(path, 'eve_local_station/' + path.relative_to(ROOT).as_posix())
    with zipfile.ZipFile(args.output) as archive:
        if archive.testzip() is not None:
            raise RuntimeError('Source archive integrity check failed')
    print(f'{len(files)} files; {args.output.stat().st_size} bytes')
    print('SHA256 ' + hashlib.sha256(args.output.read_bytes()).hexdigest())


if __name__ == '__main__':
    main()
