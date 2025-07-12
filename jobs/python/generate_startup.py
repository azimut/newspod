#!/usr/bin/env python3
import sqlite3
import json

DB_PATH = "../go/feeds.db"
DB_JSON = "./feeds.startup.json"

def main():
    con = sqlite3.connect(DB_PATH)
    cur = con.cursor()
    response = {}
    response['feeds'] = db_feeds(cur)
    response['stats'] = db_stats(cur)
    response['tags']  = db_tags(cur)
    con.close()
    print(json.dumps(response, indent=4))
    with open(DB_JSON, "w") as json_file:
        json.dump(response, json_file)


def db_tags(cur: sqlite3.Cursor):
    res = cur.execute("SELECT name FROM tags")
    return [ x[0] for x in res.fetchall() ]

def db_feeds(cur: sqlite3.Cursor):
    res = cur.execute("""
        SELECT feeds.id, feeds.title, count(*)
          FROM feeds
          JOIN entries        ON feeds.id =        entries.feedid
          JOIN feeds_metadata ON feeds.id = feeds_metadata.feedid
      GROUP BY entries.feedid
        HAVING count(*) > 0
      ORDER BY feeds_metadata.lastentry DESC """)
    return [ {"id": id, "title": title, "nEntries": count}
             for id, title, count in res.fetchall()]

def db_stats(cur: sqlite3.Cursor):
    res = cur.execute("""
        SELECT *
          FROM (SELECT COUNT(1) FROM feeds)
          JOIN (SELECT COUNT(1) FROM entries)
          JOIN (SELECT page_size*page_count FROM pragma_page_count(), pragma_page_size())""")
    nf, ne, dbsize = res.fetchall()[0]
    return {
        "nPodcasts": nf,
         "nEntries": ne,
           "dbSize": dbsize,
    }

if __name__ == '__main__':
    main()
