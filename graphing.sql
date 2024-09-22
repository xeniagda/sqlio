.headers on
.mode box
.width 100

CREATE TABLE points(x REAL NOT NULL, y REAL NOT NULL);

CREATE TABLE viewport(
    x_min REAL NOT NULL, x_max REAL NOT NULL,
    y_min REAL NOT NULL, y_max REAL NOT NULL,
    x_grading REAL NOT NULL, y_grading REAL NOT NULL,
    x_rows REAL, y_rows REAL
);

CREATE VIEW x_gradings(x_row) AS
    WITH RECURSIVE
        positive(x) AS (
            VALUES (0.0) UNION ALL
            SELECT x + x_grading AS x FROM positive, viewport
                WHERE x + x_grading < x_max
        ),
        negative(x) AS (
            VALUES (0.0) UNION ALL
            SELECT x - x_grading AS x FROM negative, viewport
                WHERE x - x_grading > x_min
        )
    SELECT DISTINCT CAST((x - x_min) / (x_max - x_min) * x_rows AS INTEGER) AS x_row
        FROM (SELECT * FROM positive UNION ALL SELECT * FROM negative), viewport
        ORDER BY x;

CREATE VIEW y_gradings(y_row) AS
    WITH RECURSIVE
        positive(y) AS (
            VALUES (0.0) UNION ALL
            SELECT y + y_grading AS y FROM positive, viewport
                WHERE y + y_grading < y_max
        ),
        negative(y) AS (
            VALUES (0.0) UNION ALL
            SELECT y - y_grading AS y FROM negative, viewport
                WHERE y - y_grading > y_min
        )
    SELECT DISTINCT CAST((y - y_min) / (y_max - y_min) * y_rows AS INTEGER) AS y_row
        FROM (SELECT * FROM positive UNION ALL SELECT * FROM negative), viewport
        ORDER BY y;

CREATE VIEW xs(x, x_row) AS
    WITH RECURSIVE
        xs(x, x_row) AS (
            SELECT x_min AS x, 0 AS x_row FROM viewport UNION ALL
            SELECT x + (x_max - x_min) / x_rows AS x, x_row + 1 FROM xs, viewport
                WHERE x_row + 1 < x_rows
        )
    SELECT * FROM xs;

CREATE VIEW ys(y, y_row) AS
    WITH RECURSIVE
        ys(y, y_row) AS (
            SELECT y_min AS y, 0 AS y_row FROM viewport UNION ALL
            SELECT y + (y_max - y_min) / y_rows AS y, y_row + 1 FROM ys, viewport
                WHERE y_row + 1 < y_rows
        )
    SELECT * FROM ys;

CREATE VIEW background_glyphs(x, x_row, y, y_row, char) AS
    SELECT x, x_row, y, y_row, (
        CASE x_row = CAST(x_rows / 2 AS INTEGER)
            WHEN 1 THEN CASE y_row IN y_gradings
                WHEN 1 THEN '╪'
                WHEN 0 THEN '│'
            END
            WHEN 0 THEN CASE y_row = CAST(y_rows / 2 AS INTEGER)
                WHEN 1 THEN CASE x_row IN x_gradings
                    WHEN 1 THEN '╫'
                    WHEN 0 THEN '─'
                END
                WHEN 0 THEN NULL
            END
        END
    ) AS char
    FROM xs, ys, viewport;


CREATE VIEW closest_point(x, x_row, y, y_row, distance_sq) AS
    WITH
        points_rows(x_row, y_row) AS (
            SELECT
                (x-x_min)/(x_max-x_min) * x_rows AS x_row,
                (y-y_min)/(y_max-y_min) * y_rows AS y_row
            FROM points, viewport
        )
    SELECT x, x_row, y, y_row, (
        SELECT min((points_rows.x_row-xs.x_row)*(points_rows.x_row-xs.x_row) + (points_rows.y_row-ys.y_row)*(points_rows.y_row-ys.y_row))
            FROM points_rows
    ) AS distance_sq
    FROM xs, ys, viewport;

CREATE VIEW foreground_glyphs(x, x_row, y, y_row, char) AS
    SELECT x, x_row, y, y_row, (
        CASE distance_sq < 0.25
            WHEN 1 THEN '█'
            WHEN 0 THEN CASE distance_sq < 0.5
                WHEN 1 THEN '░'
                WHEN 0 THEN NULL
            END
        END
    ) AS char
    FROM closest_point;

CREATE VIEW output_ascii(row) AS
    SELECT group_concat(
        CASE foreground_glyphs.char IS NOT NULL
            WHEN 1 THEN foreground_glyphs.char
            WHEN 0 THEN CASE background_glyphs.char IS NOT NULL
                WHEN 1 THEN background_glyphs.char
                WHEN 0 THEN ' '
            ENd
        END
        , ''
    ) AS row
        FROM background_glyphs JOIN foreground_glyphs USING(x_row, y_row)
        GROUP BY y_row
        ORDER BY background_glyphs.y DESC;

-- sample plot: x^3

INSERT INTO viewport(x_min, x_max, y_min, y_max, x_grading, y_grading, x_rows, y_rows) VALUES
    (-3.00, 3.0, -30.0, 30.0, 1.0, 5.0, 50.0, 25.0);

INSERT INTO points(x, y)
    SELECT x, x * x * x AS y
        FROM xs;

SELECT row FROM output_ascii;

-- sample plot: sin(x) \approx x-x^3/6+x^5/120-x^7/5040+x^9/362880
DELETE FROM points;
DELETE FROM viewport;

INSERT INTO viewport(x_min, x_max, y_min, y_max, x_grading, y_grading, x_rows, y_rows) VALUES
    (-6, 6, -1.2, 1.2, 3.1415/2, 0.5, 100, (100/6*1.2));

INSERT INTO points(x, y)
    WITH
        x_mod_2pi(x_orig, x) AS (SELECT x AS x_orig, mod(x+5*3.141592, 2*3.141592)-3.141592 AS x FROM xs)
    SELECT x_orig AS x, x - x*x*x/6 + x*x*x*x*x/120 - x*x*x*x*x*x*x/5040 + x*x*x*x*x*x*x*x*x/362880 AS y
        FROM x_mod_2pi;
SELECT row FROM output_ascii;
