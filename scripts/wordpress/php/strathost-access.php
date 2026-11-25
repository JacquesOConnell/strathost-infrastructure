<?php
// Plan 17 / D03: authenticate the protected origin independently of Cloudflare IP allowlists.
// WordPress login/roles remain required for application administration.
if (getenv('STRATHOST_VISIBILITY') !== 'secure' || PHP_SAPI === 'cli' || defined('WP_CLI') && WP_CLI ||
    defined('STRATHOST_HEALTH_REQUEST') && STRATHOST_HEALTH_REQUEST) {
    return;
}

function strathost_deny_access() {
    http_response_code(403);
    header('Cache-Control: no-store');
    exit('Access denied');
}

function strathost_base64url_decode($value) {
    if (!is_string($value) || !preg_match('/^[A-Za-z0-9_-]+$/D', $value)) {
        return false;
    }
    return base64_decode(strtr($value, '-_', '+/'), true);
}

$issuer = getenv('STRATHOST_ACCESS_ISSUER');
$audience = getenv('STRATHOST_ACCESS_AUDIENCE');
$token = $_SERVER['HTTP_CF_ACCESS_JWT_ASSERTION'] ?? '';
if (!preg_match('~^https://[a-z0-9-]+\.cloudflareaccess\.com$~D', $issuer ?: '') ||
    !$audience || strlen($token) > 16384) {
    strathost_deny_access();
}
$segments = explode('.', $token);
if (count($segments) !== 3) {
    strathost_deny_access();
}
$header = json_decode(strathost_base64url_decode($segments[0]) ?: '', true);
$claims = json_decode(strathost_base64url_decode($segments[1]) ?: '', true);
$signature = strathost_base64url_decode($segments[2]);
if (!is_array($header) || !is_array($claims) || $signature === false ||
    ($header['alg'] ?? '') !== 'RS256' || !is_string($header['kid'] ?? null) || isset($header['crit'])) {
    strathost_deny_access();
}

// Short bounded cache; fetch only the configured issuer, never a URL supplied by a JWT header.
$cache_file = '/tmp/strathost-access-certs.json';
$cached = is_file($cache_file) && filemtime($cache_file) > time() - 300
    ? json_decode(file_get_contents($cache_file), true) : null;
if (!is_array($cached) || ($cached['issuer'] ?? '') !== $issuer) {
    $context = stream_context_create(['http' => ['timeout' => 5, 'follow_location' => 0],
        'ssl' => ['verify_peer' => true, 'verify_peer_name' => true]]);
    $body = @file_get_contents($issuer . '/cdn-cgi/access/certs', false, $context, 0, 262144);
    $keys = $body === false ? null : json_decode($body, true);
    if (!is_array($keys['public_certs'] ?? null)) {
        strathost_deny_access();
    }
    $cached = ['issuer' => $issuer, 'keys' => $keys['public_certs']];
    file_put_contents($cache_file, json_encode($cached), LOCK_EX);
}
$certificate = null;
foreach ($cached['keys'] ?? [] as $key) {
    if (($key['kid'] ?? '') === $header['kid']) {
        $certificate = $key['cert'] ?? null;
        break;
    }
}
if (!$certificate || openssl_verify($segments[0] . '.' . $segments[1], $signature, $certificate, OPENSSL_ALGO_SHA256) !== 1) {
    // Unknown rotated keys fail closed; retry after the short cache interval.
    strathost_deny_access();
}
$now = time();
$audiences = $claims['aud'] ?? [];
if (!is_array($audiences)) {
    $audiences = [$audiences];
}
if (($claims['iss'] ?? '') !== $issuer || !in_array($audience, $audiences, true) ||
    !is_numeric($claims['exp'] ?? null) || $claims['exp'] <= $now ||
    !is_numeric($claims['iat'] ?? null) || $claims['iat'] > $now + 60 ||
    isset($claims['nbf']) && (!is_numeric($claims['nbf']) || $claims['nbf'] > $now + 60)) {
    strathost_deny_access();
}
// Do not grant WordPress accounts/roles based on request headers or this access token.
unset($_SERVER['HTTP_CF_ACCESS_AUTHENTICATED_USER_EMAIL']);
