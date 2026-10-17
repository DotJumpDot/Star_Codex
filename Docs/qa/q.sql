SELECT 'WEBP', count(*), coalesce(sum(bytes),0) FROM blobs WHERE path LIKE '%.webp';
SELECT 'ALL', count(*), sum(bytes) FROM blobs;
SELECT 'FRESH', path, bytes FROM blobs WHERE path LIKE '%.webp' LIMIT 3;
