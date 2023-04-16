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

	htmlContent := HTMLContent{Now: time.Now().Format(time.RFC850)}

	feeds, err := readJsonFeeds("feeds.json")
	if err != nil {
		panic(err)
	}

	for _, feed := range feeds {
		if err := feed.fetch(); err != nil {
			fmt.Fprintln(os.Stderr, err)
			continue
		}
		htmlContent.Feeds = append(htmlContent.Feeds, feed)
	}

	sort.Sort(Feeds(htmlContent.Feeds))

	tmpl := template.Must(template.ParseFiles("layout.html"))
	tmpl.Execute(os.Stdout, htmlContent)
}
