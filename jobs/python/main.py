#!/usr/bin/env python3

import os
import sys
import json
import yt_dlp
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
    if not os.path.exists(DB_PATH):
        print("db does not exists, aborting...")
        sys.exit(1)
    for url in json_urls():
        feed, entries = process_url(url)
        print(feed)
    pass


def json_urls():
    with open(DB_JSON) as f:
        return [
            feed['url']
            for feed
            in json.load(f)['feeds']
            if 'youtube.com' in feed['url']
        ]

def process_url(rss_url):
    match parse_qsl(urlparse(rss_url).query):
        case [('playlist_id', id)]:
            url = f"https://www.youtube.com/playlist?list={id}"
            return parse_playlist(url)
        case [('channel_id', id)]:
            url = f"https://www.youtube.com/channel/{id}"
            return parse_playlist(url)
        case _:
            print(f"invalid url ({url})!")
            sys.exit(1)

# TODO: PARSE input RSS url to playlist URL
# 'playlist_items': '1-10',
# +.id / .webpage_url+
# .channel (name) / .channel_id / .channel_url
def parse_playlist(url):
    with yt_dlp.YoutubeDL({
            'playlist_items': '1-3',
            'extract_flat': 'in_playlist',
            # 'quiet': True,
            'skip_download': True}) as ydl:
        info = ydl.extract_info(url, download=False)
        return (make_feed(info), make_entries(info))

def make_feed(info):
    return Feed(info['title'], info['description'], info['thumbnails'][-1]['url'], info['webpage_url'], info['epoch'], info['playlist_count'])

def make_entries(info):
    entries = []
    for rawentry in info['entries']:
        entry = Entry(rawentry['url'], rawentry['title'], rawentry['duration'], rawentry['view_count'], rawentry['channel'], rawentry['channel_url'])
        entries.append(entry)
    return entries

if __name__ == '__main__':
    main()
