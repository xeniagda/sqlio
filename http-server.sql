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

CREATE TRIGGER message_parsed AFTER INSERT ON processed_requests
BEGIN
    WITH
        req(method, path, http_version, body) AS (SELECT method, path, http_version, body FROM parsed_requests WHERE token = NEW.token),
        html(data) AS (SELECT '<html><body><h1> welcome to sqlsite! </h1> <p> you requested ' || method || ' ' || path || '</body></html>' FROM req),
        header_lines(line) AS (VALUES('HTTP/1.1 200 Ok'),('Content-Length: ' || (SELECT length(data) FROM html)),('')),
        header(data) AS (SELECT group_concat(line, char(13) || char(10)) FROM header_lines),
        response(data) AS (SELECT group_concat(data, char(13) || char(10)) FROM (SELECT data FROM header UNION ALL SELECT data FROM html))
    SELECT tcp_send(NEW.token, (SELECT data FROM response));
END;

SELECT tcp_listen('0.0.0.0:1234', 'connect_cb', 'data_cb');
SELECT write_to_file('/dev/stdout', 'listening on localhost:1234');

