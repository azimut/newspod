SELECT *
  FROM (SELECT COUNT(1) as nfeeds FROM feeds)
       JOIN (SELECT COUNT(1) as nentries FROM entries)
       JOIN (SELECT page_size*page_count as filesize FROM pragma_page_count(), pragma_page_size());
