PRAGMA trusted_schema=1;

CREATE TABLE connect_cb(token TEXT, remote_addr TEXT);
CREATE TRIGGER log_connections AFTER INSERT ON connect_cb BEGIN
    SELECT write_to_file('/dev/stdout', 'new connection [' || NEW.token || ']: ' || NEW.remote_addr || char(10));
END;

CREATE TABLE data_from(token TEXT, data TEXT, UNIQUE(token));

CREATE TABLE data_cb(token TEXT, byte TEXT);
CREATE TRIGGER accept_data_new AFTER INSERT ON data_cb
BEGIN
    -- insert into data_from if it's not there
    INSERT OR IGNORE INTO data_from (token, data) VALUES (NEW.token, '');

    UPDATE data_from SET data = data || char(NEW.byte) WHERE data_from.token = NEW.token;
END;

CREATE TRIGGER print_data_on_newline AFTER UPDATE ON data_from
    WHEN char(10) = substr(NEW.data, length(NEW.data)) -- last char is a newline
BEGIN
    SELECT write_to_file('/dev/stdout', 'data from ' || NEW.token || ': ' || substr(NEW.data, 1, -1 + length(NEW.data)) || char(10));
    UPDATE data_from SET data = '' WHERE data_from.token = NEW.token;
    SELECT tcp_send(NEW.token, 'you sent: ' || NEW.data);
END;

SELECT tcp_listen('0.0.0.0:1234', 'connect_cb', 'data_cb');
SELECT write_to_file('/dev/stdout', 'listening on localhost:1234');
