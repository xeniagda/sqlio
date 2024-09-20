PRAGMA trusted_schema=1;
.load target/debug/libsqlio
.mode box
.headers on

.read http-parse.sql

CREATE TABLE connect_cb(token TEXT, remote_addr TEXT);
CREATE TRIGGER new_connection AFTER INSERT ON connect_cb BEGIN
    SELECT write_to_file('/dev/stdout', 'new connection [' || NEW.token || ']: ' || NEW.remote_addr || char(10));
END;

CREATE TABLE data_cb(token TEXT, byte INTEGER);
CREATE TRIGGER got_data AFTER INSERT ON data_cb
BEGIN
    INSERT INTO got_byte (token, byte) VALUES (NEW.token, char(NEW.byte));
END;

CREATE TRIGGER get_index AFTER INSERT ON processed_requests
    WHEN EXISTS (SELECT * FROM parsed_requests WHERE token = NEW.token AND method = 'GET' AND (path = '/index.html' OR path = '/'))
BEGIN
    WITH
        req(method, path, http_version, body) AS (SELECT method, path, http_version, body FROM parsed_requests WHERE token = NEW.token),
        html(data) AS (
            SELECT '<html><body><h1> Welcome to SQLSite! </h1> <h3> Your headers: </h3>' || (
                SELECT group_concat('<b>' || header_key || '</b>: ' || header_value, '</br>')
                    FROM parsed_request_headers WHERE token = NEW.token
            ) || '</body></html>' FROM req),
        header_lines(line) AS (VALUES('HTTP/1.1 200 Ok'),('Content-Length: ' || (SELECT length(data) FROM html)),('')),
        header(data) AS (SELECT group_concat(line, char(13) || char(10)) FROM header_lines),
        response(data) AS (SELECT group_concat(data, char(13) || char(10)) FROM (SELECT data FROM header UNION ALL SELECT data FROM html))
    SELECT tcp_send(NEW.token, (SELECT data FROM response));
END;

SELECT tcp_listen('0.0.0.0:1234', 'connect_cb', 'data_cb');
