package main

import (
	"fmt"
	"strings"
)

const JSON_FILE = "feeds.json"
const SQL_FILE = "feeds.db"

func main() {

	feeds_json, err := LoadJson(JSON_FILE)
	if err != nil {
		panic(err)
	}

	feeds_db, err := LoadDB(SQL_FILE)
	if err != nil {
		panic(err)
	}

	fmt.Println("[+] Reconciliating RSS feeds from json and sqlite")
	feeds := Feeds{}
	for _, feed_json := range feeds_json {
		for _, feed_db := range feeds_db {
			if feed_db.Url == feed_json.Url {
				feed_json.RawId = feed_db.RawId
				feed_json.RawEtag = feed_db.RawEtag
				feed_json.RawLastFetch = feed_db.RawLastFetch
				feed_json.RawLastModified = feed_db.RawLastModified
			}
		}
		isVideoFeed := strings.Contains(feed_json.Url, "youtube.com")
		if isVideoFeed {
			feed_json.Tags = append(feed_json.Tags, "video")
		}
		if len(feed_json.Tags) == 0 {
			feed_json.Tags = append(feed_json.Tags, "uncategorized")
		}
		fmt.Println("- " + feed_json.Url)
		feeds = append(feeds, feed_json)
	}

	fmt.Println("[+] Starting RSS feeds fetch:")
	for i := range feeds {
		err := feeds[i].Fetch()
		if err == nil {
			fmt.Printf(
				"%d/%d OK (%s)\n",
				i+1,
				len(feeds),
				feeds[i].Url,
			)
		} else {
			fmt.Printf(
				"%d/%d ERROR (%s) due (%v)\n",
				i+1,
				len(feeds),
				feeds[i].Url,
				err,
			)
		}
	}

	err = feeds.Save(SQL_FILE)
	if err != nil {
		panic(err)
	}
}
