"""Disposable Linux application tests. No AWS credentials, APIs or Cloudflare account are used."""
import base64
import datetime
import http.cookies
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.x509.oid import NameOID

ROOT = Path(__file__).resolve().parents[2]
RUN_ID = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d%H%M%S')
PREFIX = 'strathost-qa-' + RUN_ID
WORK = ROOT / '.tools' / PREFIX
DATABASE_HOST = 'fixture.abcdef.eu-west-1.rds.amazonaws.com'
WRONG_HOST = 'wrong.abcdef.eu-west-1.rds.amazonaws.com'
ISSUER_HOST = 'strathost-qa.cloudflareaccess.com'
ISSUER = 'https://' + ISSUER_HOST
AUDIENCE = 'strathost-local-test-audience'
RESULTS = []
PROJECTS = []
CONTAINERS = []
VOLUMES = []
IMAGES = {}


def docker(*args, timeout=180, check=True):
    result = subprocess.run(['docker', *map(str, args)], cwd=ROOT, text=True,
                            capture_output=True, timeout=timeout)
    if check and result.returncode:
        # Never echo command arguments or full application logs: fixtures include random credentials.
        raise RuntimeError('Docker operation failed: ' + ' '.join(map(str, args[:2])) + '\n' + result.stderr[-2500:])
    return result


def passed(name, detail=''):
    RESULTS.append({'test': name, 'result': 'pass', 'detail': detail})
    print('PASS ' + name, flush=True)


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding='utf-8', newline='\n')


def certificate(key, common_name, issuer_certificate=None, issuer_key=None, names=(), ca=False):
    now = datetime.datetime.now(datetime.timezone.utc)
    subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, common_name)])
    builder = (x509.CertificateBuilder().subject_name(subject)
               .issuer_name(issuer_certificate.subject if issuer_certificate else subject)
               .public_key(key.public_key()).serial_number(x509.random_serial_number())
               .not_valid_before(now - datetime.timedelta(minutes=5))
               .not_valid_after(now + datetime.timedelta(days=2))
               .add_extension(x509.BasicConstraints(ca=ca, path_length=None), critical=True))
    if names:
        builder = builder.add_extension(x509.SubjectAlternativeName([x509.DNSName(name) for name in names]), critical=False)
    return builder.sign(issuer_key or key, hashes.SHA256())


def pem(cert):
    return cert.public_bytes(serialization.Encoding.PEM).decode()


def free_port():
    with socket.socket() as listener:
        listener.bind(('127.0.0.1', 0))
        return listener.getsockname()[1]


def compose(project, *args, check=True):
    return docker('compose', '--env-file', project['env'], '-f', ROOT / 'scripts/wordpress/compose.yaml',
                  '-f', project['override'], '-p', project['name'], *args, check=check)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


HTTP = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())


def request(project, path='/', host=None, token=None, body=None, cookie=None, extra_headers=None):
    headers = {'Host': host or project['hostname']}
    headers.update(extra_headers or {})
    if token is not None:
        headers['Cf-Access-Jwt-Assertion'] = token
    if cookie:
        headers['Cookie'] = cookie
    if body is not None:
        headers['Content-Type'] = 'application/x-www-form-urlencoded'
        body = urllib.parse.urlencode(body).encode()
    req = urllib.request.Request(f'http://127.0.0.1:{project["port"]}{path}', data=body, headers=headers)
    try:
        response = HTTP.open(req, timeout=12)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        return response.status, response.headers, response.read().decode(errors='replace')


def wait_for(operation, description, seconds=150):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            if operation():
                return
        except (OSError, RuntimeError, urllib.error.URLError):
            pass
        time.sleep(2)
    raise RuntimeError('Timed out waiting for ' + description)


def token(signing_key, kid='initial', **changes):
    now = int(time.time())
    claims = {'iss': ISSUER, 'aud': [AUDIENCE], 'iat': now - 5, 'exp': now + 300, 'email': 'fixture@example.invalid'}
    claims.update(changes)
    encode = lambda value: base64.urlsafe_b64encode(json.dumps(value, separators=(',', ':')).encode()).rstrip(b'=')
    message = encode({'alg': 'RS256', 'kid': kid, 'typ': 'JWT'}) + b'.' + encode(claims)
    signature = signing_key.sign(message, padding.PKCS1v15(), hashes.SHA256())
    return (message + b'.' + base64.urlsafe_b64encode(signature).rstrip(b'=')).decode()


def prepare():
    WORK.mkdir(parents=True)
    configuration = ROOT / '.tools/docker-cli'
    configuration.mkdir(exist_ok=True)
    write(configuration / 'config.json', '{}\n')
    os.environ['DOCKER_CONFIG'] = str(configuration)
    server = json.loads(docker('version', '--format', '{{json .Server}}').stdout)
    require(server['Os'] == 'linux', 'Linux Docker engine required')
    for role, digest in json.loads((Path(__file__).parent / 'images.json').read_text()).items():
        docker('image', 'inspect', digest)
        IMAGES[role] = digest
    write(WORK / 'images.json', json.dumps(IMAGES, indent=2))
    print('Building the production WordPress Dockerfile with the resolved base digest', flush=True)
    built = docker('build', '--build-arg', 'WORDPRESS_BASE_IMAGE=' + IMAGES['wordpress'],
                   '-t', PREFIX + ':wordpress', ROOT / 'scripts/wordpress', timeout=600)
    write(WORK / 'build.log', built.stdout + built.stderr)
    IMAGES['built_wordpress_id'] = docker('image', 'inspect', '--format', '{{.Id}}', PREFIX + ':wordpress').stdout.strip()
    passed('Production Dockerfile builds and all three PHP files pass lint')
    # Generate throwaway keys only inside this ignored run directory.
    ca_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    ca = certificate(ca_key, 'StratHost disposable test CA', ca=True)
    server_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    server_cert = certificate(server_key, DATABASE_HOST, ca, ca_key, names=(DATABASE_HOST, ISSUER_HOST))
    write(WORK / 'ca.pem', pem(ca))
    write(WORK / 'client-ca.pem', pem(ca))
    write(WORK / 'server.pem', pem(server_cert))
    write(WORK / 'server-key.pem', server_key.private_bytes(serialization.Encoding.PEM,
          serialization.PrivateFormat.TraditionalOpenSSL, serialization.NoEncryption()).decode())
    wrong_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    write(WORK / 'wrong-ca.pem', pem(certificate(wrong_key, 'Untrusted disposable CA', ca=True)))
    sign_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    sign_cert = certificate(sign_key, 'Disposable Access fixture', ca, ca_key)
    write(WORK / 'certs.json', json.dumps({'public_certs': [{'kid': 'initial', 'cert': pem(sign_cert)}]}))
    root_password = secrets.token_hex(24)
    write(WORK / 'mysql-root-password', root_password)
    write(WORK / 'mysql-client.cnf', '[client]\nuser=root\npassword=' + root_password + '\n')
    write(WORK / 'admin-password', secrets.token_hex(24))
    sql = []
    for site in ('public', 'secure', 'internal'):
        directory = WORK / site
        write(directory / 'database_user', 'wp_' + site)
        password = secrets.token_hex(24)
        write(directory / 'database_password', password)
        for name in ('auth_key', 'secure_auth_key', 'logged_in_key', 'nonce_key', 'auth_salt', 'secure_auth_salt', 'logged_in_salt', 'nonce_salt'):
            write(directory / name, secrets.token_hex(32))
        sql.extend([f'CREATE DATABASE {site}_wordpress;',
                    f"CREATE USER 'wp_{site}'@'%' IDENTIFIED BY '{password}' REQUIRE SSL;",
                    f"GRANT ALL ON {site}_wordpress.* TO 'wp_{site}'@'%';"])
    write(WORK / 'init.sql', '\n'.join(sql))
    write(WORK / 'php-ca.ini', 'openssl.cafile=/fixtures/ca.pem\n')
    write(WORK / 'install.php', '''<?php
define('WP_INSTALLING', true);
require '/var/www/html/wp-load.php';
require '/var/www/html/wp-admin/includes/upgrade.php';
add_filter('pre_wp_mail', '__return_true');
if (!is_blog_installed()) {
    wp_install('StratHost QA', 'qa_admin', 'fixture@example.invalid', true, '', trim(file_get_contents('/fixtures/admin-password')));
}
echo 'QA_INSTALLED';
''')
    write(WORK / 'db-probe.php', '''<?php
require '/var/www/html/wp-load.php';
global $wpdb;
$cipher = $wpdb->get_row("SHOW SESSION STATUS LIKE 'Ssl_cipher'", ARRAY_N);
echo $cipher && $cipher[1] ? 'QA_DB_TLS_OK' : 'QA_DB_TLS_MISSING';
''')
    docker('network', 'create', '--internal', '--label', 'strathost.qa=' + RUN_ID, PREFIX)
    tls_volume = PREFIX + '-tls'
    docker('volume', 'create', '--label', 'strathost.qa=' + RUN_ID, tls_volume)
    VOLUMES.append(tls_volume)
    docker('run', '--rm', '-v', str(WORK) + ':/fixtures:ro', '-v', tls_volume + ':/tls',
           '--entrypoint', 'bash', IMAGES['wordpress'], '-c',
           'cp /fixtures/ca.pem /fixtures/server.pem /fixtures/server-key.pem /tls/; chmod 644 /tls/*')
    db = PREFIX + '-mysql'
    CONTAINERS.append(db)
    docker('run', '-d', '--name', db, '--label', 'strathost.qa=' + RUN_ID, '--network', PREFIX,
           '--network-alias', DATABASE_HOST, '--network-alias', WRONG_HOST,
           '-v', tls_volume + ':/tls:ro', '-v', str(WORK) + ':/fixtures:ro',
           '-v', str(WORK / 'init.sql') + ':/docker-entrypoint-initdb.d/init.sql:ro',
           '-e', 'MYSQL_ROOT_PASSWORD_FILE=/fixtures/mysql-root-password', IMAGES['mysql'],
           '--ssl-ca=/tls/ca.pem', '--ssl-cert=/tls/server.pem', '--ssl-key=/tls/server-key.pem', '--require-secure-transport=ON')
    wait_for(lambda: docker('exec', db, 'mysqladmin', '--defaults-extra-file=/fixtures/mysql-client.cnf', '--protocol=tcp', '--host=127.0.0.1', 'ping', '--silent', check=False).returncode == 0,
             'MySQL TLS startup')
    write(WORK / 'jwks.conf', '''server {
listen 443 ssl;
ssl_certificate /tls/server.pem;
ssl_certificate_key /tls/server-key.pem;
location = /cdn-cgi/access/certs { alias /fixtures/certs.json; default_type application/json; }
}''')
    jwks = PREFIX + '-jwks'
    CONTAINERS.append(jwks)
    docker('run', '-d', '--name', jwks, '--network', PREFIX, '--network-alias', ISSUER_HOST,
           '--label', 'strathost.qa=' + RUN_ID, '-v', tls_volume + ':/tls:ro', '-v', str(WORK) + ':/fixtures:ro',
           '-v', str(WORK / 'jwks.conf') + ':/etc/nginx/conf.d/default.conf:ro', IMAGES['nginx'])
    return sign_key, ca, ca_key


def site(name, visibility):
    hostname = visibility + '.example.test'
    directory = WORK / name
    directory.mkdir(exist_ok=True)
    # Exercise the actual production proxy template, not a separately maintained imitation.
    deploy_source = (ROOT / 'scripts/wordpress/deploy.sh').read_text()
    template = deploy_source.split('cat > "/etc/strathost/wordpress/$site/proxy.conf" <<EOF\n', 1)[1].split('\nEOF', 1)[0]
    write(directory / 'proxy.conf', template.replace('$hostname', hostname).replace('\\$proxy_add_x_forwarded_for', '$proxy_add_x_forwarded_for'))
    upload_volume = PREFIX + '-uploads-' + visibility
    if upload_volume not in VOLUMES:
        docker('volume', 'create', '--label', 'strathost.qa=' + RUN_ID, upload_volume)
        VOLUMES.append(upload_volume)
        docker('run', '--rm', '-v', upload_volume + ':/data', '--entrypoint', 'bash', IMAGES['wordpress'],
               '-c', 'chown 33:33 /data; chmod 750 /data')
    port = free_port()
    project = {'name': PREFIX + '-' + name, 'hostname': hostname, 'port': port,
               'env': directory / 'site.env', 'override': directory / 'override.json'}
    settings = {
        'WORDPRESS_IMAGE': IMAGES['built_wordpress_id'], 'NGINX_IMAGE': IMAGES['nginx'],
        'DATABASE_HOST': DATABASE_HOST, 'DATABASE_NAME': visibility + '_wordpress',
        'SITE_HOSTNAME': hostname, 'PRIVATE_IP': '127.0.0.1', 'PROXY_PORT': str(port), 'VISIBILITY': visibility,
        'UPLOADS_PATH': directory.as_posix(), 'RDS_CA_FILE': (WORK / 'client-ca.pem').as_posix(),
        'PROXY_CONFIG': (directory / 'proxy.conf').as_posix(), 'SECRETS_DIRECTORY': (WORK / visibility).as_posix(),
        'ACCESS_ISSUER': ISSUER if visibility == 'secure' else '', 'ACCESS_AUDIENCE': AUDIENCE if visibility == 'secure' else '',
        'WORDPRESS_MEMORY_LIMIT': '256m'
    }
    write(project['env'], ''.join(key + '=' + value + '\n' for key, value in settings.items()))
    override = {'services': {'wordpress': {'networks': ['site', 'database'],
                'volumes': [str(WORK) + ':/fixtures:ro', str(WORK / 'php-ca.ini') + ':/usr/local/etc/php/conf.d/qa-ca.ini:ro',
                            {'type': 'volume', 'source': 'uploads', 'target': '/var/www/html/wp-content/uploads'}]}},
                # Docker Desktop does not publish loopback ports for an internal-only site bridge.
                # Keep each site's bridge separate and publish only to 127.0.0.1; DB/JWKS stay internal.
                'networks': {'site': {'internal': False}, 'database': {'external': True, 'name': PREFIX}},
                'volumes': {'uploads': {'external': True, 'name': upload_volume}}}
    write(project['override'], json.dumps(override, indent=2))
    PROJECTS.append(project)
    compose(project, 'up', '-d')
    project['container'] = compose(project, 'ps', '-q', 'wordpress').stdout.strip()
    wait_for(lambda: docker('exec', project['container'], 'test', '-f', '/var/www/html/wp-config.php', check=False).returncode == 0,
             name + ' WordPress entrypoint')
    installed = docker('exec', project['container'], 'php', '/fixtures/install.php')
    write(directory / 'installation.log', installed.stdout + installed.stderr)
    if 'QA_INSTALLED' not in installed.stdout:
        diagnostic = docker('exec', project['container'], 'php', '-r', '''
mysqli_report(MYSQLI_REPORT_OFF);
$db = mysqli_init();
mysqli_options($db, MYSQLI_OPT_SSL_VERIFY_SERVER_CERT, true);
mysqli_ssl_set($db, null, null, '/etc/ssl/certs/rds-ca-bundle.pem', null, null);
$ok = mysqli_real_connect($db, getenv('WORDPRESS_DB_HOST') ? explode(':', getenv('WORDPRESS_DB_HOST'))[0] : '',
 trim(file_get_contents('/run/secrets/database_user')), trim(file_get_contents('/run/secrets/database_password')),
 getenv('WORDPRESS_DB_NAME'), 3306, null, MYSQLI_CLIENT_SSL);
echo $ok ? 'Direct mysqli TLS succeeded' : mysqli_connect_error();
''', check=False)
        write(directory / 'tls-diagnostic.log', diagnostic.stdout + diagnostic.stderr)
    require('QA_INSTALLED' in installed.stdout, name + ': database installation failed')
    return project


def test_applications(signing_key, ca, ca_key):
    public = site('public-a', 'public')
    replica = site('public-b', 'public')
    secure = site('secure', 'secure')
    internal = site('internal', 'internal')
    for project in PROJECTS:
        wait_for(lambda: request(project, '/healthz', host='127.0.0.1')[0] == 200, project['name'] + ' readiness')
    passed('All four application replicas pass real WordPress/database/uploads readiness')
    for project in (public, internal):
        require(request(project)[0] == 200, 'Expected application homepage')
    passed('Public and internal application pages render through the production proxy template')
    require(request(public, host='wrong.example.test')[0] == 403, 'Wrong host exposed content')
    for path in ('/healthz', '/strathost-health.php', '/strathost-health.php/extra'):
        require(request(secure, path)[0] == 403, 'Named host exposed diagnostic route: ' + path)
    passed('Wrong Host and external diagnostic routes are rejected')
    for label, candidate in [
        ('missing', None), ('malformed', 'not-a-jwt'), ('expired', token(signing_key, exp=int(time.time()) - 1)),
        ('unsigned', 'eyJhbGciOiJub25lIiwia2lkIjoiaW5pdGlhbCJ9.e30.eA'),
        ('wrong audience', token(signing_key, aud=['other-application'])), ('wrong issuer', token(signing_key, iss='https://other.cloudflareaccess.com')),
        ('future issued', token(signing_key, iat=int(time.time()) + 600)), ('not yet valid', token(signing_key, nbf=int(time.time()) + 600)),
        ('unknown signing key', token(signing_key, kid='unknown')),
        ('forged signature', token(rsa.generate_private_key(public_exponent=65537, key_size=2048)))
    ]:
        require(request(secure, token=candidate)[0] == 403, 'Access token unexpectedly accepted: ' + label)
        passed('Access rejects ' + label + ' token')
    require(request(secure, token=token(signing_key))[0] == 200, 'Valid Access token rejected')
    passed('Valid signed Access token succeeds after HTTPS JWKS retrieval with trusted fixture CA')
    status, headers, _ = request(secure, '/wp-admin/', token=token(signing_key))
    require(status == 302 and 'wp-login.php' in headers.get('Location', ''),
            'Access token must not create a WordPress administrator session')
    passed('Valid Access token still requires a separate WordPress administrator login')
    require(request(secure, extra_headers={'Cf-Access-Authenticated-User-Email': 'fixture@example.invalid'})[0] == 403,
            'An identity header without a signed token bypassed Access')
    passed('Forged identity header alone does not authenticate a protected request')
    # Rotate the public key and expire only the dedicated local test container's cache.
    rotated_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    rotated_cert = certificate(rotated_key, 'Rotated disposable Access key', ca, ca_key)
    write(WORK / 'certs.json', json.dumps({'public_certs': [{'kid': 'rotated', 'cert': pem(rotated_cert)}]}))
    docker('exec', secure['container'], 'php', '-r', "touch('/tmp/strathost-access-certs.json', time()-301);")
    require(request(secure, token=token(rotated_key, kid='rotated'))[0] == 200, 'Rotated signing key rejected after cache expiry')
    passed('Rotated Access signing key succeeds after bounded cache refresh')
    docker('stop', PREFIX + '-jwks')
    docker('exec', secure['container'], 'php', '-r', "touch('/tmp/strathost-access-certs.json', time()-301);")
    try:
        require(request(secure, token=token(rotated_key, kid='rotated'))[0] == 403, 'Issuer outage bypassed expired cache')
        passed('Access fails closed when signing-key endpoint is unavailable and cache has expired')
    finally:
        docker('start', PREFIX + '-jwks')
    require(request(secure, token=token(rotated_key, kid='rotated'))[0] == 200, 'Access did not recover')
    passed('Access recovers after signing-key endpoint returns')
    probe = docker('exec', public['container'], 'php', '/fixtures/db-probe.php').stdout
    require('QA_DB_TLS_OK' in probe, 'Database TLS not established')
    passed('Production wpdb drop-in establishes verified encrypted MySQL connection')
    probe = docker('exec', public['container'], 'env', 'WORDPRESS_DB_HOST=' + WRONG_HOST + ':3306', 'php', '/fixtures/db-probe.php').stdout
    require('Database unavailable' in probe and 'QA_DB_TLS_OK' not in probe, 'Wrong database hostname was accepted')
    passed('Database certificate hostname mismatch fails closed')
    write(WORK / 'client-ca.pem', (WORK / 'wrong-ca.pem').read_text())
    try:
        probe = docker('exec', public['container'], 'php', '/fixtures/db-probe.php').stdout
        require('Database unavailable' in probe and 'QA_DB_TLS_OK' not in probe, 'Untrusted database CA was accepted')
        require(request(public, '/healthz', host='127.0.0.1')[0] != 200, 'Untrusted database remained ready')
        passed('Untrusted database CA fails connection and readiness')
    finally:
        write(WORK / 'client-ca.pem', (WORK / 'ca.pem').read_text())
    require('QA_DB_TLS_OK' in docker('exec', public['container'], 'php', '/fixtures/db-probe.php').stdout, 'TLS did not recover')
    passed('Database connectivity recovers after restoring the trusted CA')
    probe = docker('exec', public['container'], 'env', 'WORDPRESS_DB_NAME=secure_wordpress', 'php', '/fixtures/db-probe.php').stdout
    require('Database unavailable' in probe and 'QA_DB_TLS_OK' not in probe, 'Fixture site user accessed another site database')
    passed('Application fails closed when its database user lacks access to the selected database')
    docker('exec', '-u', 'www-data', public['container'], 'php', '-r', "file_put_contents('/var/www/html/wp-content/uploads/shared-proof.txt', 'shared-upload-proof');")
    upload = docker('exec', '-u', 'www-data', replica['container'], 'php', '-r', "echo file_get_contents('/var/www/html/wp-content/uploads/shared-proof.txt');").stdout
    require(upload == 'shared-upload-proof', 'Replicas did not share uploads')
    passed('Two public replicas read the same uploaded file from shared test storage')
    docker('exec', public['container'], 'chmod', '000', '/var/www/html/wp-content/uploads')
    try:
        require(request(public, '/healthz', host='127.0.0.1')[0] != 200, 'Unwritable uploads remained ready')
        passed('Unwritable uploads fail application readiness')
    finally:
        docker('exec', public['container'], 'chmod', '750', '/var/www/html/wp-content/uploads')
    require(request(public, '/healthz', host='127.0.0.1')[0] == 200, 'Uploads readiness did not recover')
    passed('Application readiness recovers after restoring uploads permissions')
    password = (WORK / 'admin-password').read_text()
    status, headers, _ = request(public, '/wp-login.php', body={'log': 'qa_admin', 'pwd': password, 'wp-submit': 'Log In',
                                         'redirect_to': 'https://' + public['hostname'] + '/wp-admin/', 'testcookie': '1'},
                                         cookie='wordpress_test_cookie=WP%20Cookie%20check')
    cookies = http.cookies.SimpleCookie()
    for item in headers.get_all('Set-Cookie', []):
        cookies.load(item)
    require(status in (302, 303) and any(name.startswith('wordpress_logged_in_') for name in cookies), 'WordPress login failed')
    cookie = '; '.join(name + '=' + value.value for name, value in cookies.items())
    status, _, body = request(replica, '/wp-admin/', cookie=cookie)
    require(status == 200 and 'Dashboard' in body, 'Login session did not survive replica change')
    passed('WordPress administrator session remains valid across replicas using shared salts/database')
    docker('stop', PREFIX + '-mysql')
    try:
        require(request(public, '/healthz', host='127.0.0.1')[0] != 200, 'Database outage remained ready')
        passed('Database outage makes application readiness fail')
    finally:
        docker('start', PREFIX + '-mysql')
    wait_for(lambda: request(public, '/healthz', host='127.0.0.1')[0] == 200, 'database outage recovery')
    passed('Application readiness recovers after database restart')
    # Directly exercise the production mount guard in Linux without credentials or host mounts.
    guard = docker('run', '--rm', '-v', str(ROOT / 'scripts/wordpress/start-site.sh') + ':/guard.sh:ro',
                   '--entrypoint', 'bash', IMAGES['wordpress'], '/guard.sh', 'public_wordpress', check=False)
    require(guard.returncode == 1 and not guard.stderr.strip(),
            'Missing-mount test must exit through its guard, not a shell/runtime error')
    passed('Linux startup helper refuses a missing uploads mount before secret retrieval')


def cleanup():
    for project in reversed(PROJECTS):
        compose(project, 'down', '--volumes', '--remove-orphans', check=False)
    for container in CONTAINERS:
        docker('rm', '-f', '-v', container, check=False)
    for volume in VOLUMES:
        docker('volume', 'rm', volume, check=False)
    docker('network', 'rm', PREFIX, check=False)


def main():
    failure = None
    try:
        key, ca, ca_key = prepare()
        test_applications(key, ca, ca_key)
    except Exception as error:
        failure = str(error)
        print('FAIL ' + failure, flush=True)
        RESULTS.append({'test': 'Application integration run', 'result': 'fail', 'detail': failure})
        for container in CONTAINERS:
            logs = docker('logs', container, check=False)
            write(WORK / (container + '.log'), logs.stdout + logs.stderr)
    finally:
        cleanup()
        write(WORK / 'results.json', json.dumps({'run': RUN_ID, 'images': IMAGES, 'results': RESULTS,
              'limits': 'Local MySQL and shared Docker volume fixtures; no AWS RDS/EFS/VPN/Checkmk or Cloudflare account integration.'}, indent=2))
    if failure:
        raise SystemExit(1)
    print(f'{len(RESULTS)} checks passed. Results: {WORK / "results.json"}', flush=True)


if __name__ == '__main__':
    main()
