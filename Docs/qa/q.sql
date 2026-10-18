SELECT 'S', id, title, type, origin FROM series ORDER BY id;
SELECT 'SRC', series_id, source_id, source_url FROM series_sources WHERE series_id > 5;
