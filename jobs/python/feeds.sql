SELECT feeds.id,
       feeds.title,
       count(DISTINCT entries.id) as len,
       group_concat(DISTINCT tags.name) as tags
  FROM feeds
       JOIN entries        ON feeds.id =        entries.feedid
       JOIN feeds_metadata ON feeds.id = feeds_metadata.feedid
       JOIN  feed_tags     ON feeds.id =      feed_tags.feedid
       JOIN       tags     ON  tags.id =      feed_tags.tagid
 GROUP BY entries.feedid
 ORDER BY feeds_metadata.lastentry DESC;
