#!/usr/bin/env python3

import os
import sys
import json
import yt_dlp
from urllib.parse import urlparse, parse_qsl


DB_PATH = "../go/feeds.db"
DB_JSON = "../go/feeds.json"


def main():
    if not os.path.exists(DB_PATH):
        print("db does not exists, aborting...")
        sys.exit(1)
    for url in json_urls():
        print(process_url(url))
    pass


def json_urls():
    with open(DB_JSON) as f:
        return [
            feed['url']
            for feed
            in json.load(f)['feeds']
            if 'youtube.com' in feed['url']
        ]

def process_url(url):
    match parse_qsl(urlparse(url).query):
        case [('playlist_id', id)]:
            print( "playlist: " + id)
            # parse_playlist(url)
            # parse_playlist("https://www.youtube.com/playlist?list=PLFs19LVskfNxGjRZu_d_i93aSDraOSiJa")
            parse_playlist("https://www.youtube.com/watch?v=bQirAkkxC6A")
        case [('channel_id', id)]:
            print("channel: " + id)
        case _:
            print(f"invalid url ({url})!")
            sys.exit(1)

def parse_playlist(url):
    with yt_dlp.YoutubeDL(
            {
                'extract_flat': 'in_playlist',
                'youtube_include_dash_manifest': False,  # Exclude dash manifests
                # 'force_generic_extractor': True,
                # 'dumpjson': True
            }) as ydl:
        infos = ydl.extract_info(url, download=False)
        print("debug: ", infos)
        # video_ids = [video for video in infos['entries']]
        # print(video_ids)


if __name__ == '__main__':
    main()
