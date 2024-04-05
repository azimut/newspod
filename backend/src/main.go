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
		keep := true
		for _, feed_db := range feeds_db {
			if feed_db.Url == feed_json.Url {
				if err = feed_db.UpdateMetadata(db); err != nil {
					keep = false
					fmt.Printf("dropping feed with error (%v)\n", err)
				} else {
					fmt.Printf("to be added feed (%s)\n", feed_db.Url)
				}
			}
		}
		if !keep {
			continue
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
