package main

import (
	"fmt"
)

func main() {

	db, err := InitDB("./feeds.db")
	if err != nil {
		panic(err)
	}

	feeds_json, err := LoadJson("feeds.json")
	if err != nil {
		panic(err)
	}

	feeds_db, err := LoadDb(db)
	if err != nil {
		panic(err)
	}

	feeds := Feeds{}
	for _, feed_json := range feeds_json {
		fmt.Printf("processing json feed (%s)\n", feed_json.Url)
		for _, feed_db := range feeds_db {
			if feed_db.Url == feed_json.Url {
				feed_json.RawId = feed_db.RawId
				feed_json.RawEtag = feed_db.RawEtag
				feed_json.RawLastFetch = feed_db.RawLastFetch
				feed_json.RawLastModified = feed_db.RawLastModified
			}
		}
		fmt.Printf("adding feed: %s\n", feed_json.Url)
		feeds = append(feeds, feed_json)
	}

	fmt.Println("Starting RSS feeds fetch...")
	for i := range feeds {
		err := feeds[i].Fetch()
		if err == nil {
			fmt.Printf(
				"[%02d/%02d] success (%s)\n",
				i+1,
				len(feeds),
				feeds[i].Url,
			)
		} else {
			fmt.Printf(
				"[%02d/%02d] failure (%s) with error (%v)\n",
				i+1,
				len(feeds),
				feeds[i].Url,
				err,
			)
		}
	}

	feeds.Sort()

	err = feeds.Save(db)
	if err != nil {
		panic(err)
	}
}
