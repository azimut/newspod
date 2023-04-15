package main

import (
	"fmt"
	"os"
	"sort"
	"time"

	"html/template"
)

type HTMLContent struct {
	Feeds []Feed
	Now   string
}

func main() {
	content := HTMLContent{Now: time.Now().Format(time.RFC850)}
	feeds, err := readJsonFeeds("feeds.json")
	if err != nil {
		panic(err)
	}

	for _, feed := range feeds {
		if err := feed.fetch(); err != nil {
			fmt.Fprintln(os.Stderr, err)
			continue
		}
		content.Feeds = append(content.Feeds, feed)
	}

	sort.Slice(content.Feeds, func(i, j int) bool {
		if len(content.Feeds[i].Entries) == 0 || len(content.Feeds[j].Entries) == 0 {
			return false
		}
		return content.Feeds[j].Entries[0].Date.Before(content.Feeds[i].Entries[0].Date)
	})

	tmpl := template.Must(template.ParseFiles("layout.html"))
	tmpl.Execute(os.Stdout, content)
}
