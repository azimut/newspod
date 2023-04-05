package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strings"
	"time"

	"html/template"

	"github.com/dustin/go-humanize"
	"github.com/mmcdole/gofeed"
)

const INPUT_FEEDS = "feeds.txt"
const OUTPUT_TEMPLATE = "layout.html"

type Entry struct {
	Title       string
	Url         string
	Date        time.Time
	MachineDate string
	HumanDate   string
}

type Feed struct {
	Url     string
	Title   string
	Entries []Entry
}

type Content struct {
	Feeds []Feed
	Now   string
}

func readLines(inputFeeds string) (feeds []Feed) {
	f, err := os.Open(inputFeeds)
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

func (feed *Feed) fillEntries() error {
	fp := gofeed.NewParser()
	rawFeed, err := fp.ParseURL(feed.Url)
	if err != nil {
		return err
	}

	feed.Title = rawFeed.Title
	for _, item := range rawFeed.Items {
		entry := Entry{
			entryTitle(item.Title, feed.Title),
			entryUrl(*item),
			*item.PublishedParsed,
			item.PublishedParsed.Format("2006-1-2 15:4"),
			humanize.Time(*item.PublishedParsed),
		}
		feed.Entries = append(feed.Entries, entry)
	}
	return nil
}

func entryTitle(itemTitle string, feedTitle string) string {
	tmp1 := strings.TrimSpace(strings.TrimPrefix(itemTitle, feedTitle))
	tmp2 := strings.TrimPrefix(tmp1, "Episode ")
	tmp3 := strings.TrimPrefix(tmp2, "Ep ")
	tmp4 := strings.TrimPrefix(tmp3, "SE Radio ")
	return tmp4
}

func entryUrl(item gofeed.Item) string {
	if len(item.Enclosures) > 0 {
		return item.Enclosures[0].URL
	}
	if strings.Contains(item.Link, "www.youtube.com") {
		return strings.Replace(item.Link, "www.youtube.com", "piped.kavin.rocks", 1) + "&listen=1"
	}
	return item.Link
}

func NewContent() Content {
	return Content{Now: time.Now().Format("2006-1-2 15:4")}
}

func main() {
	content := NewContent()
	for _, feed := range readLines(INPUT_FEEDS) {
		if err := feed.fillEntries(); err != nil {
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

	tmpl := template.Must(template.ParseFiles(OUTPUT_TEMPLATE))
	tmpl.Execute(os.Stdout, content)
}
