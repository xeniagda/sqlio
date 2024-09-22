.read log.sql
INSERT INTO log_rules(module, min_level) VALUES ('http-parse', 'notice');

-- input table
CREATE TABLE got_byte
    ( token TEXT
    , byte TEXT
    );

-- output tables
CREATE TABLE parsed_requests
    ( token TEXT
    , method TEXT DEFAULT NULL -- GET, POST, etc
    , path TEXT DEFAULT NULL
    , http_version TEXT DEFAULT NULL
    , body TEXT DEFAULT NULL
    );

CREATE TABLE parsed_request_headers
    ( token TEXT REFERENCES parsed_requests(token)
    , header_key TEXT NOT NULL
    , header_value TEXT NOT NULL
    );

-- whenever a message is finished parsing, it's token appears in this table
-- put a TRIGGER on this table to handle requests
-- whenever a request is finished, parsed_requests.{method,path,http_version} are all guaranteed not to be NULL
CREATE TABLE processed_requests
    ( token TEXT REFERENCES parsed_requests(token)
    );

CREATE TABLE request_state
    ( token TEXT REFERENCES parsed_requests(token)
    -- state is one of
    -- 'method', 'path', 'version' - we are currently parsing the method/path/version
    -- 'header-key' - parsing the LHS of a header field
    -- 'header-space' - after processing the colon between the header key and header value
    -- 'header-value' - parsing the RHS of a header field
    -- 'body' - parsing the body of the message
    -- 'done' - terminal state, no more processing occurs
    , state TEXT NOT NULL
    , current_header_key TEXT DEFAULT NULL -- NULL if we are not currently parsing a header key or value
    , body_bytes_left INT DEFAULT NULL -- NULL if no Content-Length header has yet been set
    , UNIQUE(token)
    );

CREATE TRIGGER new_message AFTER INSERT ON got_byte
    WHEN NOT EXISTS(SELECT * FROM parsed_requests WHERE parsed_requests.token = NEW.token)
BEGIN
    INSERT INTO log(module, level, message) VALUES ('http-parse', 'notice', 'got a new message from ' || NEW.token);

    INSERT INTO parsed_requests (token, method, http_version) VALUES
        ( NEW.token
        , NEW.byte -- the first byte is the first token in the method
        , NULL
        );
    INSERT INTO request_state (token, state) VALUES
        ( NEW.token
        , 'method'
        );
END;

CREATE TRIGGER method AFTER INSERT ON got_byte
    WHEN EXISTS(SELECT * FROM request_state WHERE request_state.token = NEW.token AND state = 'method')
     AND NEW.byte != ' '
BEGIN
    INSERT INTO log(module, level, message) VALUES ('http-parse', 'debug', 'method byte from ' || NEW.token || ': ' || quote(NEW.byte));

    UPDATE parsed_requests
        SET method = method || NEW.byte
        WHERE token = NEW.token;
END;

CREATE TRIGGER transition_to_path AFTER INSERT ON got_byte
    WHEN EXISTS(SELECT * FROM request_state WHERE request_state.token = NEW.token AND state = 'method')
     AND NEW.byte == ' '
BEGIN
    INSERT INTO log(module, level, message) VALUES ('http-parse', 'info', 'transitioning ' || NEW.token || ' to path');

    UPDATE request_state
        SET state = 'path'
        WHERE token = NEW.token;
    UPDATE parsed_requests
        SET path = ''
        WHERE token = NEW.token;
END;

CREATE TRIGGER path AFTER INSERT ON got_byte
    WHEN EXISTS(SELECT * FROM request_state WHERE request_state.token = NEW.token AND state = 'path')
     AND NEW.byte != ' '
BEGIN
    INSERT INTO log(module, level, message) VALUES ('http-parse', 'debug', 'path byte from ' || NEW.token || ': ' || quote(NEW.byte));

    UPDATE parsed_requests
        SET path = path || NEW.byte
        WHERE token = NEW.token;
END;

CREATE TRIGGER transition_to_version AFTER INSERT ON got_byte
    WHEN EXISTS(SELECT * FROM request_state WHERE request_state.token = NEW.token AND state = 'path')
     AND NEW.byte == ' '
BEGIN
    INSERT INTO log(module, level, message) VALUES ('http-parse', 'info', 'transitioning ' || NEW.token || ' to version');

    UPDATE request_state
        SET state = 'version'
        WHERE token = NEW.token;
    UPDATE parsed_requests
        SET http_version = ''
        WHERE token = NEW.token;
END;

CREATE TRIGGER version AFTER INSERT ON got_byte
    WHEN EXISTS(SELECT * FROM request_state WHERE request_state.token = NEW.token AND state = 'version')
     AND NEW.byte != char(13) AND NEW.byte != char(10)
BEGIN
    INSERT INTO log(module, level, message) VALUES ('http-parse', 'debug', 'version byte from ' || NEW.token || ': ' || quote(NEW.byte));

    UPDATE parsed_requests
        SET http_version = http_version || NEW.byte
        WHERE token = NEW.token;
END;

CREATE TRIGGER transition_to_header_key AFTER INSERT ON got_byte
    WHEN EXISTS(SELECT * FROM request_state WHERE request_state.token = NEW.token AND (state = 'version' OR state = 'header-value'))
     AND NEW.byte == char(10)
BEGIN
    INSERT INTO log(module, level, message) VALUES ('http-parse', 'info', 'transitioning ' || NEW.token || ' to header key');

    UPDATE request_state
        SET state = 'header-key'
          , current_header_key = ''
        WHERE token = NEW.token;
END;

CREATE TRIGGER header_key AFTER INSERT ON got_byte
    WHEN EXISTS(SELECT * FROM request_state WHERE request_state.token = NEW.token AND state = 'header-key')
     AND NEW.byte != ':'
BEGIN
    INSERT INTO log(module, level, message) VALUES ('http-parse', 'debug', 'header key byte from ' || NEW.token || ': ' || quote(NEW.byte));

    UPDATE request_state
        SET current_header_key = current_header_key || NEW.byte
        WHERE token = NEW.token;
END;

CREATE TRIGGER transition_to_header_space AFTER INSERT ON got_byte
    WHEN EXISTS(SELECT * FROM request_state WHERE request_state.token = NEW.token AND state = 'header-key')
     AND NEW.byte == ':'
BEGIN
    INSERT INTO log(module, level, message) VALUES ('http-parse', 'info', 'transitioning ' || NEW.token || ' to header space');

    UPDATE request_state
        SET state = 'header-space'
        WHERE token = NEW.token;
END;

CREATE TRIGGER transition_to_header_value AFTER INSERT ON got_byte
    WHEN EXISTS(SELECT * FROM request_state WHERE request_state.token = NEW.token AND state = 'header-space')
     AND NEW.byte == ' '
BEGIN
    INSERT INTO log(module, level, message) VALUES ('http-parse', 'info', 'transitioning ' || NEW.token || ' to header value');

    INSERT INTO parsed_request_headers (token, header_key, header_value)
        SELECT token, current_header_key, ''
            FROM request_state
            WHERE token = NEW.token;

    UPDATE request_state
        SET state = 'header-value'
        WHERE token = NEW.token;
END;

CREATE TRIGGER header_value AFTER INSERT ON got_byte
    WHEN EXISTS(SELECT * FROM request_state WHERE request_state.token = NEW.token AND state = 'header-value')
     AND NEW.byte != char(13) AND NEW.byte != char(10)
BEGIN
    INSERT INTO log(module, level, message) VALUES ('http-parse', 'debug', 'header value byte from ' || NEW.token || ': ' || quote(NEW.byte));

    UPDATE parsed_request_headers
        SET header_value = header_value || NEW.byte
        WHERE token = NEW.token AND header_key = (
            SELECT current_header_key FROM request_state WHERE request_state.token = NEW.token
        );
END;

CREATE TRIGGER no_body AFTER INSERT ON got_byte
    WHEN EXISTS(SELECT * FROM request_state WHERE request_state.token = NEW.token AND state = 'header-key')
     AND NOT EXISTS(SELECT * FROM parsed_request_headers WHERE parsed_request_headers.token = NEW.token AND header_key = 'Content-Length')
     AND NEW.byte == char(10)
BEGIN
    INSERT INTO log(module, level, message) VALUES ('http-parse', 'notice', 'message from ' || NEW.token || ' terminated without body');

    UPDATE request_state
        SET state = 'done'
        WHERE token = NEW.token;

    INSERT INTO processed_requests ( token ) VALUES
        ( NEW.token );
END;

CREATE TRIGGER transition_to_body AFTER INSERT ON got_byte
    WHEN EXISTS(SELECT * FROM request_state WHERE request_state.token = NEW.token AND state = 'header-key')
     AND EXISTS(SELECT * FROM parsed_request_headers WHERE parsed_request_headers.token = NEW.token AND header_key = 'Content-Length')
     AND NEW.byte == char(10)
BEGIN
    INSERT INTO log(module, level, message) VALUES ('http-parse', 'info', 'transitioning ' || NEW.token || ' to body');

    UPDATE request_state
        SET state = 'body'
          , body_bytes_left = (SELECT CAST(header_value AS INTEGER) FROM parsed_request_headers WHERE parsed_request_headers.token = NEW.token AND header_key = 'Content-Length')
        WHERE token = NEW.token;

    UPDATE parsed_requests
        SET body = ''
        WHERE token = NEW.token;

END;

CREATE TRIGGER body AFTER INSERT ON got_byte
    WHEN EXISTS(SELECT * FROM request_state WHERE request_state.token = NEW.token AND state = 'body' AND body_bytes_left > 1)
BEGIN
    INSERT INTO log(module, level, message) VALUES ('http-parse', 'debug', 'body byte from ' || NEW.token || ': ' || quote(NEW.byte));

    UPDATE request_state
        SET body_bytes_left = body_bytes_left - 1
        WHERE token = NEW.token;

    UPDATE parsed_requests
        SET body = body || NEW.byte
        WHERE token = NEW.token;
END;

CREATE TRIGGER body_end AFTER INSERT ON got_byte
    WHEN EXISTS(SELECT * FROM request_state WHERE request_state.token = NEW.token AND state = 'body' AND body_bytes_left == 1)
BEGIN
    INSERT INTO log(module, level, message) VALUES ('http-parse', 'notice', 'message from ' || NEW.token || ' ended with body');

    UPDATE parsed_requests
        SET body = body || NEW.byte
        WHERE token = NEW.token;

    INSERT INTO processed_requests ( token ) VALUES
        ( NEW.token );
END;
