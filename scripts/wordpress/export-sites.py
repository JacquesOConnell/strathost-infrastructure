#!/usr/bin/env python3
"""Docker01 logical exports. These are not atomic database/filesystem snapshots."""
import datetime
import gzip
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import tarfile
import tempfile


def option_value(value):
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '\\r') + '"'


def main():
    if os.geteuid() != 0:
        raise SystemExit('Run as root on Docker01')
    addresses = subprocess.check_output(['ip', '-4', '-o', 'address', 'show'], text=True)
    if '10.0.4.10/' not in addresses:
        raise SystemExit('Only Docker01 schedules application exports')
    settings = json.loads(pathlib.Path('/etc/strathost/wordpress/exports.json').read_text())
    bucket = settings['bucket']
    if not re.fullmatch(r'strathost-(dev|test|prod)-euw1-backup-[0-9]{12}', bucket):
        raise SystemExit('Expected this environment\'s application export bucket')
    timestamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    for site in ('public_wordpress', 'secure_wordpress', 'internal_wordpress'):
        config = json.loads(pathlib.Path(f'/etc/strathost/wordpress/{site}.json').read_text())
        uploads = pathlib.Path(f'/srv/wordpress/{site}/uploads')
        if not os.path.ismount(uploads):
            raise SystemExit('Required EFS mount is missing')
        with tempfile.TemporaryDirectory(prefix=f'strathost-export-{site}-', dir='/var/tmp') as directory:
            root = pathlib.Path(directory)
            # Runtime files are populated at service startup from the site-specific secret.
            secrets = pathlib.Path(f'/run/strathost/{site}')
            options = root / 'client.cnf'
            options.write_text('[client]\nuser=' + option_value((secrets / 'database_user').read_text()) +
                               '\npassword=' + option_value((secrets / 'database_password').read_text()) + '\n')
            options.chmod(0o600)
            sql = root / 'database.sql'
            with sql.open('wb') as stream:
                result = subprocess.run(['mysqldump', f'--defaults-extra-file={options}', '--host', config['database_host'],
                                         '--ssl-mode=VERIFY_IDENTITY', '--ssl-ca', config['rds_ca_file'],
                                         '--single-transaction', '--quick', '--no-tablespaces', '--set-gtid-purged=OFF',
                                         config['database_name']], stdout=stream, stderr=subprocess.PIPE, timeout=900)
            if result.returncode:
                raise SystemExit('Database export failed; credential-bearing diagnostics were not printed')
            options.unlink()
            with sql.open('rb') as source, gzip.open(root / 'database.sql.gz', 'wb') as target:
                shutil.copyfileobj(source, target)
            sql.unlink()
            with tarfile.open(root / 'uploads.tar.gz', 'w:gz') as archive:
                archive.add(uploads, arcname='uploads', recursive=True)
            files = {}
            for name in ('database.sql.gz', 'uploads.tar.gz'):
                with (root / name).open('rb') as stream:
                    files[name] = {'sha256': hashlib.file_digest(stream, 'sha256').hexdigest(), 'bytes': (root / name).stat().st_size}
            manifest = {'site': site, 'started_at_utc': timestamp, 'files': files,
                        'consistency': 'Transactional database dump and live uploads archive; no atomic cross-service guarantee'}
            (root / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
            # Write manifest last. Its presence marks a fully uploaded logical export set.
            for name in ('database.sql.gz', 'uploads.tar.gz', 'manifest.json'):
                subprocess.run(['aws', 's3', 'cp', str(root / name), f's3://{bucket}/sites/{site}/daily/{timestamp}/{name}',
                                '--region', 'eu-west-1', '--only-show-errors', '--checksum-algorithm', 'SHA256'],
                               check=True, capture_output=True, timeout=900)
            print(f'Uploaded the {site} logical export set; restore verification remains required')


if __name__ == '__main__':
    try:
        main()
    except (OSError, KeyError, ValueError, subprocess.SubprocessError):
        raise SystemExit('Application export failed; inspect host storage, IAM and service diagnostics')
