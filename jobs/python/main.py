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
class Feed:
    rssurl:      str
    title:       str         = field(init=False)
    description: str         = field(init=False)
    thumbnail:   str         = field(init=False)
    url:         str         = field(init=False)
    epoch:       int         = field(init=False)
    count:       int | None  = field(init=False)
    channel:     str         = field(init=False)
    forward:     bool        = True
    id:          int         = 0

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
        with yt_dlp.YoutubeDL({
                'playlist_items': '0',
                'extract_flat': 'in_playlist',
                # 'quiet': True,
                # 'daterange': yt_dlp.utils.DateRange('2025-07-01', '9999-12-31'),
                'skip_download': True}) as ydl:
            info = ydl.extract_info(self.url, download=False)
            self.title = info['title']
            self.description = info['description']
            self.thumbnail = info['thumbnails'][-1]['url']
            self.url = info['webpage_url']
            self.epoch = info['epoch']
            self.count = info['playlist_count']
            self.channel = info['channel']

@dataclass
class Entry:
    url: str
    title: str
    duration: int
    views: int
    channel: str
    channel_url: str

def main():
    con = sqlite3.connect(DB_PATH)
    cur = con.cursor()

    for rss_url in json_urls(DB_JSON):
        feed = Feed(rss_url)
        feed.fetch()
        print(feed)
        break
        # id = db_feed_id(rss_url, cur)
        # if id:
        #     feed.id = id
        # else:
        #     feed.id = db_add(feed, cur)
        # lastentry = db_lastentry(id, cur)
        # print(rss_url, id, lastentry)

    con.close()

def json_urls(file: str) -> list[str]:
    with open(file) as f:
        return [
            feed['url']
            for feed
            in json.load(f)['feeds']
            if 'youtube.com' in feed['url']
        ]

def make_entries(info):
    entries = []
    for rawentry in info['entries']:
        entry = Entry(rawentry['url'], rawentry['title'], rawentry['duration'], rawentry['view_count'], rawentry['channel'], rawentry['channel_url'])
        entries.append(entry)
    return entries


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

def db_lastentry(id: int, cur: sqlite3.Cursor):
    res = cur.execute("SELECT lastentry FROM feeds_metadata WHERE feedid = ?", (id,))
    row = res.fetchone()
    if row: return row[0]


if __name__ == '__main__':
    main()
