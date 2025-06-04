package main

import (
	"fmt"
)

func main() {

	feeds_json, err := LoadJson("feeds.json")
	if err != nil {
		panic(err)
	}

	feeds_db, err := LoadDb("feeds.db")
	if err != nil {
		panic(err)
	}

	fmt.Println("[+] Reconciliating RSS feeds from json and sqlite:")
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
		fmt.Println(feed_json.Url)
		feeds = append(feeds, feed_json)
	}

	fmt.Println("[+] Starting RSS feeds fetch:")
	for i := range feeds {
		err := feeds[i].Fetch()
		if err == nil {
			fmt.Printf(
				"%02d/%02d OK (%s)\n",
				i+1,
				len(feeds),
				feeds[i].Url,
			)
		} else {
			fmt.Printf(
				"%02d/%02d ERROR (%s) due (%v)\n",
				i+1,
				len(feeds),
				feeds[i].Url,
				err,
			)
		}
	}

	feeds.Sort()

	err = feeds.Save("feeds.db")
	if err != nil {
		panic(err)
	}
}
