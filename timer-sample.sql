PRAGMA trusted_schema=1;

CREATE VIRTUAL TABLE write_to_file USING write_to_file;

CREATE TABLE callback (token VARCHAR);
CREATE TRIGGER print_callback AFTER INSERT ON callback BEGIN
    INSERT INTO write_to_file (contents, path, ty) VALUES ('got callback: ' || NEW.token || char(10), '/dev/stdout', 'write');
END;

CREATE VIRTUAL TABLE timer USING timer;
INSERT INTO timer (n_millis, insert_table, value) VALUES
    (1000, 'callback', 'one second'),
    (3000, 'callback', 'three seconds'),
    (2000, 'callback', 'two seconds');

