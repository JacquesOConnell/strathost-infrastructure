<?php
// Plan 13: explicitly verify the RDS certificate, including on reconnect.
// This small wpdb drop-in retains WordPress query handling; test against the pinned image release.
class StratHostTLSDatabase extends wpdb {
    public function db_connect($allow_bail = true) {
        mysqli_report(MYSQLI_REPORT_OFF);
        $this->ready = false;
        $host = $this->parse_db_host($this->dbhost);
        if (!$host || !preg_match('/^[a-z0-9.-]+\.eu-west-1\.rds\.amazonaws\.com$/D', $host[0])) {
            return $this->connection_failure($allow_bail);
        }
        $this->dbh = mysqli_init();
        mysqli_options($this->dbh, MYSQLI_OPT_CONNECT_TIMEOUT, 5);
        mysqli_options($this->dbh, MYSQLI_OPT_SSL_VERIFY_SERVER_CERT, true);
        mysqli_ssl_set($this->dbh, null, null, '/etc/ssl/certs/rds-ca-bundle.pem', null, null);
        $connected = @mysqli_real_connect($this->dbh, $host[0], $this->dbuser, $this->dbpassword,
            $this->dbname, $host[1] ?: 3306, null, MYSQLI_CLIENT_SSL);
        if (!$connected) {
            return $this->connection_failure($allow_bail);
        }
        $result = mysqli_query($this->dbh, "SHOW SESSION STATUS LIKE 'Ssl_cipher'");
        $cipher = $result ? mysqli_fetch_row($result) : null;
        if (!$cipher || empty($cipher[1])) {
            mysqli_close($this->dbh);
            return $this->connection_failure($allow_bail);
        }
        $this->is_mysql = true;
        $this->init_charset();
        $this->set_charset($this->dbh);
        $this->ready = true;
        $this->set_sql_mode();
        $this->select($this->dbname, $this->dbh);
        return $this->ready;
    }

    private function connection_failure($allow_bail) {
        $this->dbh = null;
        if ($allow_bail) {
            http_response_code(503);
            exit('Database unavailable');
        }
        return false;
    }
}
$wpdb = new StratHostTLSDatabase(DB_USER, DB_PASSWORD, DB_NAME, DB_HOST);
