#!/usr/bin/env python3

import os
import sys
import json
import yt_dlp
import sqlite3
from urllib.parse import urlparse, parse_qsl
from dataclasses import dataclass


DB_PATH = "../go/feeds.db"
DB_JSON = "../go/feeds.json"

@dataclass
class Feed:
    title: str
    description: str
    thumbnail: str
    url: str
    epoch: int
    count: int
    channel: str
    rssurl: str = ""
    forward: bool = True
    id: int = 0

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

    for rss_url in json_urls():
        feed = fetch(rss_url)
        id = db_feed_id(rss_url, cur)
        if id:
            feed.id = id
        else:
            feed.id = db_add(feed, cur)
        lastentry = db_lastentry(id, cur)
        print(rss_url, id, lastentry)

    con.close()


def json_urls():
    with open(DB_JSON) as f:
        return [
            feed['url']
            for feed
            in json.load(f)['feeds']
            if 'youtube.com' in feed['url']
        ]

def fetch(rss_url: str) -> Feed:
    match parse_qsl(urlparse(rss_url).query):
        case [('playlist_id', id)]:
            url = f"https://www.youtube.com/playlist?list={id}"
            feed = parse_playlist(url)
        case [('channel_id', id)]:
            url = f"https://www.youtube.com/channel/{id}"
            feed = parse_playlist(url)
        case _:
            print(f"invalid url ({url})!")
            sys.exit(1)
    feed.rssurl = rss_url
    return feed

# TODO: PARSE input RSS url to playlist URL
# +.id / .webpage_url+
# .channel (name) / .channel_id / .channel_url
def parse_playlist(url):
    with yt_dlp.YoutubeDL({
            'playlist_items': '0',
            'extract_flat': 'in_playlist',
            # 'quiet': True,
            # 'daterange': yt_dlp.utils.DateRange('2025-07-01', '9999-12-31'),
            'skip_download': True}) as ydl:
        info = ydl.extract_info(url, download=False)
        return make_feed(info)

def make_feed(info):
    return Feed(info['title'], info['description'], info['thumbnails'][-1]['url'], info['webpage_url'], info['epoch'], info['playlist_count'], info['channel'])

def make_entries(info):
    entries = []
    for rawentry in info['entries']:
        entry = Entry(rawentry['url'], rawentry['title'], rawentry['duration'], rawentry['view_count'], rawentry['channel'], rawentry['channel_url'])
        entries.append(entry)
    return entries


def db_add(feed, cur):
    cur.execute("INSERT INTO feeds(title,url) VALUES(?,?)", (feed.title,feed.rssurl,))
    id = cur.lastrowid
    cur.execute("INSERT INTO feeds_details(feedid,home,description,language,image,author) VALUES (?,?,?,?,?,?)",
                (id,feed.url,feed.description,"en",feed.thumbnail,feed.channel,))
    cur.execute("INSERT INTO feeds_metadata(feedid) VALUES(?)", (id,))
    return id

def db_feed_id(rss_url, cur):
    res = cur.execute("SELECT id FROM feeds WHERE url = ?", (rss_url,))
    row = res.fetchone()
    if row: return row[0]

def db_lastentry(id: int, cur):
    res = cur.execute("SELECT lastentry FROM feeds_metadata WHERE feedid = ?", (id,))
    row = res.fetchone()
    if row: return row[0]


if __name__ == '__main__':
    main()
