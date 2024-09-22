.read http-parse.sql
.headers on
.mode box

INSERT INTO got_byte (token, byte)
    WITH RECURSIVE
        request(line) AS (VALUES
            ('GET /index.html HTTP/1.1'),
            ('Host: www.example.com'),
            ('Accept-Language: en'),
            (''),
            ('')),
        request_lines AS (SELECT group_concat(line, char(13) || char(10)) FROM request),
        chars(ch, rest) AS (
            VALUES(NULL, (SELECT * FROM request_lines))
            UNION ALL
            SELECT SUBSTR(rest, 1, 1) AS ch, substr(rest, 2) AS rest FROM chars WHERE length(rest) > 0
        )
        SELECT '<simple-get>' AS token, ch AS byte FROM chars WHERE ch IS NOT NULL;

INSERT INTO got_byte (token, byte)
    WITH RECURSIVE
        request(line) AS (VALUES
            ('POST /mjau.html HTTP/1.1'),
            ('Host: www.example.com'),
            ('Content-Length: 7'),
            (''),
            ('skibidi')),
        request_lines AS (SELECT group_concat(line, char(13) || char(10)) FROM request),
        chars(ch, rest) AS (
            VALUES(NULL, (SELECT * FROM request_lines))
            UNION ALL
            SELECT SUBSTR(rest, 1, 1) AS ch, substr(rest, 2) AS rest FROM chars WHERE length(rest) > 0
        )
        SELECT '<post-request>' AS token, ch AS byte FROM chars WHERE ch IS NOT NULL;

SELECT * FROM processed_requests JOIN parsed_requests USING (token) JOIN parsed_request_headers USING (token);
