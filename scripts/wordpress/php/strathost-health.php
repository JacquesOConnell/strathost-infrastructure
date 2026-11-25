<?php
// Plan 16: readiness requires WordPress bootstrap, a working database and mounted uploads.
// This endpoint is only routed by the host proxy's direct ALB health-check location.
define('STRATHOST_HEALTH_REQUEST', true);
require '/var/www/html/wp-load.php';
global $wpdb;
$uploads = '/var/www/html/wp-content/uploads';
$database_ready = (string) $wpdb->get_var('SELECT 1') === '1';
if (!$database_ready || !is_dir($uploads) || !is_writable($uploads)) {
    http_response_code(503);
    exit('Not ready');
}
header('Content-Type: text/plain');
echo 'Ready';
