PRAGMA trusted_schema=1;
.load target/debug/libsqlio


CREATE TABLE IF NOT EXISTS log
    ( level TEXT DEFAULT 'debug' -- debug, info, notice, queer, trouble, urgent
    , module TEXT
    , message TEXT NOT NULL
    , at DATETIME DEFAULT (datetime('now', 'subsec'))
    , CHECK (level = 'debug' OR level = 'info' OR level = 'notice' OR level = 'queer' OR level = 'trouble' OR level = 'unwanted' OR level = 'urgent')
    );

CREATE TABLE IF NOT EXISTS log_rules
    ( module TEXT -- if NULL, then applies to all modules
    , min_level TEXT
    );

CREATE TRIGGER IF NOT EXISTS log_write AFTER INSERT ON log
    WHEN EXISTS (SELECT * FROM log_rules WHERE NEW.level >= min_level AND module = NEW.module)
      OR EXISTS (SELECT * FROM log_rules WHERE NEW.level >= min_level AND module IS NULL)
     AND NOT EXISTS (SELECT * FROM log_rules WHERE module = NEW.module)
BEGIN
    WITH
        escape_color(num) AS (VALUES(
            CASE NEW.level
                WHEN 'debug' THEN 10 -- light green
                WHEN 'info' THEN 2 -- green
                WHEN 'notice' THEN 4 -- blue
                WHEN 'queer' THEN 3 -- yellow
                WHEN 'trouble' THEN 9 -- light red
                WHEN 'urgent' THEN 1 -- dark red
            END
        )),
        escape_code(start, end) AS (
            SELECT
                char(27) || '[38;5;' || num || 'm' AS start,
                char(27) || '[0m' AS end
            FROM escape_color
        ),
        longest_module(len) AS (
            SELECT max(length(module)) as len FROM log_rules
        ),
        output(msg) AS (
            SELECT
                escape_code.start || '['
                || NEW.at || '] '
                || NEW.level
                || escape_code.end
                || substr('       ', length(NEW.level))
                || ' ' || NEW.module
                || printf('%.*c', 1 + longest_module.len - length(NEW.module), ' ')
                || '│ ' || NEW.message || char(10)
            FROM escape_code, longest_module
        )
    SELECT write_to_file('/dev/stdout', msg) FROM output;
END;

CREATE TABLE IF NOT EXISTS log_test (_);
CREATE TRIGGER IF NOT EXISTS log_test AFTER INSERT ON log_test
BEGIN
    INSERT INTO log_rules(module, min_level) VALUES
        (NULL, 'queer'),
        ('http-parser', 'info'),
        ('http-server', 'debug'),
        ('loud-module', 'trouble');

    INSERT INTO log(level, module, message) VALUES
        ('debug', 'unspecified', 'this should not show'),
        ('debug', 'http-server', 'this should show'),
        ('debug', 'http-parser', 'this should not show'),
        ('info', 'unspecified', 'this should not show'),
        ('info', 'http-server', 'this should show'),
        ('info', 'http-parser', 'this should show'),
        ('queer', 'unspecified', 'this should show'),
        ('queer', 'http-parser', 'this should show'),
        ('queer', 'loud-module', 'this should not show'),
        ('trouble', 'unspecified', 'this should show'),
        ('trouble', 'loud-module', 'this should show');
END;
