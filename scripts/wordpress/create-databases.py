#!/usr/bin/env python3
"""One-time attended database initialization; administrator credentials stay outside Terraform."""
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile


def option_value(value):
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '\\r') + '"'


def main():
    if os.geteuid() != 0 or len(sys.argv) != 4:
        raise SystemExit('Usage: sudo python3 create-databases.py ROOT_ONLY_ADMIN.json CONFIG_DIRECTORY RDS_CA.pem')
    admin_file = pathlib.Path(sys.argv[1])
    if admin_file.is_symlink() or admin_file.stat().st_uid != 0 or admin_file.stat().st_mode & 0o077:
        raise SystemExit('Administrator input must be root-owned and mode 0600 or stricter')
    admin = json.loads(admin_file.read_text())
    if not re.fullmatch(r'[a-z0-9.-]+\.eu-west-1\.rds\.amazonaws\.com', admin['host']):
        raise SystemExit('Expected the approved RDS endpoint')
    with tempfile.TemporaryDirectory(prefix='strathost-db-', dir='/run') as temporary:
        options = pathlib.Path(temporary) / 'client.cnf'
        options.write_text('[client]\nuser=' + option_value(admin['username']) + '\npassword=' + option_value(admin['password']) + '\n')
        options.chmod(0o600)
        for site in ('public_wordpress', 'secure_wordpress', 'internal_wordpress'):
            config = json.loads((pathlib.Path(sys.argv[2]) / f'{site}.json').read_text())
            if config['database_host'] != admin['host'] or config['database_name'] != site:
                raise SystemExit('Site configuration does not match the approved database allocation')
            response = subprocess.run(['aws', 'secretsmanager', 'get-secret-value', '--region', 'eu-west-1',
                                       '--secret-id', config['secret_arn'], '--query', 'SecretString', '--output', 'text',
                                       '--no-cli-pager'], check=True, capture_output=True, text=True, timeout=30)
            secret = json.loads(response.stdout)
            username = secret['database_user']
            password = secret['database_password']
            if not re.fullmatch(r'[a-z][a-z0-9_]{0,31}', username) or username == admin['username'] or not password or '\x00' in password:
                raise SystemExit('Invalid site credentials; never reuse the database administrator')
            # A fixed SQL mode gives unambiguous quoting even when passwords contain backslashes.
            quoted_password = "'" + password.replace("'", "''") + "'"
            statements = ["SET SESSION sql_mode='NO_BACKSLASH_ESCAPES';", f'CREATE DATABASE IF NOT EXISTS `{site}` CHARACTER SET utf8mb4;']
            for private_ip in ('10.0.4.10', '10.0.5.10', '10.0.6.10'):
                account = f"'{username}'@'{private_ip}'"
                statements.extend([
                    f'CREATE USER IF NOT EXISTS {account} IDENTIFIED BY {quoted_password} REQUIRE SSL;',
                    f'ALTER USER {account} IDENTIFIED BY {quoted_password} REQUIRE SSL;',
                    f'GRANT ALL PRIVILEGES ON `{site}`.* TO {account};'
                ])
            result = subprocess.run(['mysql', f'--defaults-extra-file={options}', '--host', admin['host'], '--port', '3306',
                                     '--ssl-mode=VERIFY_IDENTITY', '--ssl-ca', sys.argv[3]], input='\n'.join(statements),
                                    capture_output=True, text=True, timeout=60)
            if result.returncode:
                raise SystemExit('Database initialization failed; inspect service diagnostics without printing SQL/credentials')
            print(f'Configured the {site} database and site-only grants for the three fixed hosts')


if __name__ == '__main__':
    try:
        main()
    except (KeyError, OSError, ValueError, subprocess.SubprocessError):
        raise SystemExit('Initialization failed; verify approved files, IAM access and database connectivity')
