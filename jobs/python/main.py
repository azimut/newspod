#!/usr/bin/env python3

import os
import sys
import json
import yt_dlp
import sqlite3
from urllib.parse import urlparse, parse_qsl
from dataclasses import dataclass, field


DB_PATH = "../go/feeds.db"
DB_JSON = "../go/feeds.json"

@dataclass
class Entry:
    url:         str
    title:       str
    duration:    int
    views:       int
    channel:     str
    channel_url: str
    feedid:      int
    description: str = field(default=False)
    # thumbnail
    # view|comment|like / _count
    # uploaded_date: "YYYYMMDD"
    # fulltitle
    # duration_string

@dataclass
class Feed:
    rssurl:      str
    title:       str         = field(init=False)
    description: str         = field(init=False)
    thumbnail:   str         = field(init=False)
    url:         str         = field(init=False)
    count:       int | None  = field(init=False)
    channel:     str         = field(init=False)
    forward:     bool        = True
    id:          int         = 0
    entries:     list[Entry] = field(default_factory=list)

    def from_rss(self) -> str:
        match parse_qsl(urlparse(self.rssurl).query):
            case [('playlist_id', id)]:
                return f"https://www.youtube.com/playlist?list={id}"
            case [('channel_id', id)]:
                return f"https://www.youtube.com/channel/{id}"
            case _:
                print(f"invalid url ({url})!")
                sys.exit(1)

    # .channel (name) / .channel_id / .channel_url
    def fetch(self):
        self.url = self.from_rss()
        with yt_dlp.YoutubeDL({ 'playlist_items': '0', 'extract_flat': 'in_playlist'}) as ydl:
            info = ydl.extract_info(self.url, download=False)
            # print(info)
            self.title       = info['title']
            self.description = info['description']
            self.thumbnail   = info['thumbnails'][-1]['url']
            self.url         = info['webpage_url']
            self.count       = info['playlist_count']
            self.channel     = info['channel']

    def fetch_entries(self):
        """fetches all entries on given feed"""
        with yt_dlp.YoutubeDL({ 'extract_flat': 'in_playlist' }) as ydl:
            info = ydl.extract_info(self.url, download=False)
            self.entries = []
            for rawentry in info['entries']:
                url = rawentry['url']
                if not 'youtube.com' in url: # skip private or other (?)
                    print("Skipping: ", rawentry)
                    continue
                entry = Entry(url, rawentry['title'], rawentry['duration'], rawentry['view_count'], rawentry['channel'], rawentry['channel_url'], self.id)
                self.entries.append(entry)

def fetch_info(video_url):
    opts = { 'extract_flat': True, 'extractor_args': {'youtube': {'player_client': ['android'] }} } # we expect "android" to fail
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(video_url, download=False)
        return (info['description'], info['timestamp'])

def main():

    con = sqlite3.connect(DB_PATH)
    cur = con.cursor()
    rss_urls = json_urls(DB_JSON)

    for rss_url in rss_urls:
        if 'channel' in rss_url: continue # unsupported, None on playlist_count and modified_date
        feed = Feed(rss_url)
        feed.fetch()

        id = db_feed_id(rss_url, cur)
        feed.id = id if id else db_add(feed, cur)

        if feed.count > db_count_entries(id, cur):
            feed.fetch_entries()
            for entry in feed.entries:
                db_insert_entry(entry, cur)

    print("[+] Running INSERTs")
    con.commit()

    print("[+] Populating empty entries")
    for rss_url in rss_urls:
        fid = db_feed_id(rss_url, cur)
        for eid, eurl, in db_select_entries_empty(fid, cur)[1:10]:
            description, timestamp = fetch_info(eurl)
            description = "..." if description == "" else description
            db_update_entry(eid, description, timestamp, cur)
    con.commit()

    print("[+] Optimizing database")
    cur.execute("INSERT INTO search(search) VALUES('optimize')")
    con.commit()
    cur.execute("VACUUM")
    con.close()

def json_urls(file: str) -> list[str]:
    with open(file) as f:
        return [
            feed['url']
            for feed
            in json.load(f)['feeds']
            if 'youtube.com' in feed['url']
        ]


def db_add(feed: str, cur: sqlite3.Cursor) -> int:
    cur.execute("INSERT INTO feeds(title,url) VALUES(?,?)", (feed.title,feed.rssurl,))
    id = cur.lastrowid
    cur.execute("INSERT INTO feeds_details(feedid,home,description,language,image,author) VALUES (?,?,?,?,?,?)",
                (id,feed.url,feed.description,"en",feed.thumbnail,feed.channel,))
    cur.execute("INSERT INTO feeds_metadata(feedid) VALUES(?)", (id,))
    return id

def db_feed_id(rss_url: str, cur: sqlite3.Cursor):
    res = cur.execute("SELECT id FROM feeds WHERE url = ?", (rss_url,))
    row = res.fetchone()
    if row: return row[0]

def db_count_entries(feedid: int, cur: sqlite3.Cursor):
    res = cur.execute("SELECT COUNT(*) FROM entries WHERE feedid = ?", (feedid,))
    row = res.fetchone()
    if row: return row[0]

def db_insert_entry(entry: Entry, cur: sqlite3.Cursor):
    res = cur.execute("SELECT COUNT(*) FROM entries WHERE url = ?", (entry.url,))
    n, = res.fetchone()
    entry_not_found = n == 0
    if entry_not_found:
        cur.execute("INSERT INTO entries(feedid,datemillis,title,url) VALUES(?,?,?,?)",
                    (entry.feedid, 0, entry.title, entry.url))
        cur.execute("INSERT INTO entries_content(entriesid,title) VALUES(?,?)",
                    (cur.lastrowid, entry.title,))

def db_select_entries_empty(feedid: int, cur: sqlite3.Cursor):
    res = cur.execute("""
      SELECT entries.id, entries.url
        FROM entries
        JOIN entries_content
          ON entries.id=entries_content.entriesid
       WHERE entries.feedid = ?
         AND (entries.datemillis = 0 OR entries_content.description is NULL OR entries_content.description = '')
      """, (feedid,))
    return res.fetchall()

def db_update_entry(eid: int, description: str, timestamp: int, cur: sqlite3.Cursor):
    cur.execute("UPDATE entries SET datemillis = ? WHERE id = ?",
                (timestamp * 1000, eid,))
    cur.execute("UPDATE entries_content SET description = ? WHERE entriesid = ?",
                (description, eid,))

if __name__ == '__main__':
    main()
