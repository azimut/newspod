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
    with open("feeds.sql") as file: res = cur.execute(file.read())
    return [ {"id": id, "title": title, "nEntries": count, "tags": tags.split(",")}
             for id, title, count, tags
             in res.fetchall() ]

def db_stats(cur: sqlite3.Cursor):
    with open("stats.sql") as file: res = cur.execute(file.read())
    nf, ne, dbsize = res.fetchall()[0]
    return {
        "nPodcasts": nf,
         "nEntries": ne,
           "dbSize": dbsize,
    }

if __name__ == '__main__':
    main()
