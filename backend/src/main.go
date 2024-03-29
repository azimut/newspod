package main

import (
	"fmt"
	"os"
)

func main() {

	feeds, err := readJsonFeeds("feeds.json")
	if err != nil {
		panic(err)
	}

	for i := range feeds {
		if err := feeds[i].fetch(); err != nil {
			fmt.Fprintf(os.Stderr, "processing of url (%s) failed (%v)\n", feeds[i].Url, err)
			continue
		}
	}

	feeds.Sort()

	err = feeds.Save()
	if err != nil {
		panic(err)
	}
}
