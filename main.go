package main

import (
	"bufio"
	"os"
	"sort"
	"strings"
	"time"

	"html/template"

	"github.com/dustin/go-humanize"
	"github.com/mmcdole/gofeed"
)

const INPUT_FEEDS = "feeds.txt"
const TEMPLATE = "layout.html"

type Entry struct {
	Title       string
	Url         string
	Format      string
	Date        time.Time
	MachineDate string
	HumanDate   string
}

type Feed struct {
	Url     string
	Title   string
	Entries []Entry
}

func getFeeds() (feeds []Feed) {
	f, err := os.Open(INPUT_FEEDS)
	if err != nil {
		panic(err)
	}
	scanner := bufio.NewScanner(f)
	scanner.Split(bufio.ScanLines)
	for scanner.Scan() {
		url := scanner.Text()
		if strings.HasPrefix(url, "#") {
			continue
		}
		feeds = append(feeds, Feed{Url: url})
	}
	return
}

func (feed *Feed) getEntries() {
	fp := gofeed.NewParser()
	rawFeed, err := fp.ParseURL(feed.Url)
	if err != nil {
		panic(err)
	}

	feed.Title = rawFeed.Title

	for _, item := range rawFeed.Items {
		for _, enclosure := range item.Enclosures {
			entry := Entry{
				item.Title,
				enclosure.URL,
				enclosure.Type,
				*item.PublishedParsed,
				item.PublishedParsed.Format("2006-1-2 15:4"),
				humanize.Time(*item.PublishedParsed),
			}
			feed.Entries = append(feed.Entries, entry)
		}
	}
}

func main() {
	var feeds []Feed
	for _, feed := range getFeeds() {
		feed.getEntries()
		feeds = append(feeds, feed)
	}
	sort.Slice(feeds, func(i, j int) bool {
		if len(feeds[i].Entries) == 0 || len(feeds[j].Entries) == 0 {
			return false
		}
		return feeds[j].Entries[0].Date.Before(feeds[i].Entries[0].Date)
	})
	tmpl := template.Must(template.ParseFiles(TEMPLATE))
	tmpl.Execute(os.Stdout, feeds)
}
