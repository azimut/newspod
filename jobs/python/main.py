#!/usr/bin/env python3

import os
import sys
import json
import yt_dlp
import sqlite3
from urllib.parse import urlparse, parse_qsl
from dataclasses import dataclass, field
from dateutil.parser import parse


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
    modified:    int         = 0                 # modified_date in playlists
    forward:     bool        = True
    id:          int         = 0
    entries:     list[Entry] = field(default_factory=list)

    def from_rss(self) -> str:
        url = urlparse(self.rssurl)
        if not url:
            print("invalid url")
            sys.exit(1)
        match parse_qsl(url.query):
            case [('playlist_id', id)]:
                return f"https://www.youtube.com/playlist?list={id}"
            case [('channel_id', id)]:
                return f"https://www.youtube.com/channel/{id}"
            case _:
                print(f"invalid url: ({url})")
                sys.exit(1)

    # .channel (name) / .channel_id / .channel_url
    def thumbnail(raw_thumbnails) -> str:
        """returns the most suitable thumbnail url from the given ones"""
        thumbnails = [ x for x in raw_thumbnails if 'width' in x and not 'preference' in x ]
        url, width = thumbnails[0]['url'], thumbnails[0]['width']
        for thumb in thumbnails:
            if thumb['width'] > width:
                url, width = thumb['url'], thumb['width']
        return url

    def fetch(self):
        self.url = self.from_rss()
        with yt_dlp.YoutubeDL({ 'playlist_items': '0', 'extract_flat': 'in_playlist'}) as ydl:
            info = ydl.extract_info(self.url, download=False)
            # print(info)
            self.title       = info['title']
            self.description = info['description']
            self.thumbnail   = self.thumbnail(info['thumbnails'])
            self.url         = info['webpage_url']
            self.count       = info['playlist_count']
            self.channel     = info['channel']
            if 'playlist' in self.rssurl:
                self.modified = int(parse(info['modified_date']).timestamp())

    def fetch_entries(self):
        """fetches all entries on given feed"""
        with yt_dlp.YoutubeDL({ 'extract_flat': 'in_playlist' }) as ydl:
            info = ydl.extract_info(self.url, download=False)
            self.entries = []
            for rawentry in info['entries']:
                if not 'view_count' in rawentry: continue # upcoming video
                url = rawentry['url']
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
        feed = Feed(rss_url)

        try:
            feed.fetch()
        except:
            print(f"rss_url = {rss_url}")
            continue

        print(feed)

        feed.id = db_feed_id(rss_url, cur)
        db_update_details(feed, cur)
        current_nentries = db_count_entries(feed.id, cur)
        print(current_nentries)

        should_fetch_entries = False
        if 'channel' in rss_url: should_fetch_entries = current_nentries > 15
        if 'playlist' in rss_url: should_fetch_entries = feed.count > current_nentries
        if should_fetch_entries:
            feed.fetch_entries()
            for entry in feed.entries:
                db_insert_entry(entry, cur)

    print("[+] Running INSERTs")
    con.commit()

    # Skip description fetch on github actions (needs a cookie)
    if 'GITHUB_REPOSITORY' not in os.environ:
        print("[+] Populating empty entries")
        for rss_url in rss_urls:
            fid = db_feed_id(rss_url, cur)
            for eid, eurl, in db_select_entries_empty(fid, cur):
                description, timestamp = fetch_info(eurl) # FIXME: check if eurls are available
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


def db_update_details(feed: Feed, cur: sqlite3.Cursor):
    cur.execute("""UPDATE feeds_details
                      SET home        = ?,
                          description = ?,
                          language    = ?,
                          image       = ?,
                          author      = ?
                    WHERE feedid      = ?""",
                (feed.url,feed.description,"en",feed.thumbnail,feed.channel,feed.id,))

def db_feed_id(rss_url: str, cur: sqlite3.Cursor):
    """get feed.id, we assume it should exist"""
    res = cur.execute("SELECT id FROM feeds WHERE url = ?", (rss_url,))
    row = res.fetchone()
    return row[0]

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
        cur.execute("INSERT INTO entries_content(entriesid,title,description) VALUES(?,?,'')",
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
