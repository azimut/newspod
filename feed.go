package main

import (
	"strings"
	"time"

	"github.com/dustin/go-humanize"
	"github.com/mmcdole/gofeed"
)

type Feed struct {
	Entries      []Entry
	RawTitle     string
	Title        string   `json:"title"`
	TrimPrefixes []string `json:"trim_prefixes"`
	TrimSuffixes []string `json:"trim_suffixes"`
	Url          string   `json:"url"`
}

type Entry struct {
	Date        time.Time
	HumanDate   string
	MachineDate string
	Title       string
	Url         string
}

type Feeds []Feed

func (a Feeds) Less(i, j int) bool {
	iDate := a[i].Entries[0].Date
	jDate := a[j].Entries[0].Date
	return iDate.After(jDate)
}

func (a Feeds) Len() int {
	return len(a)
}

func (a Feeds) Swap(i, j int) {
	a[i], a[j] = a[j], a[i]
}

func (feed *Feed) fetch() error {

	rawFeed, err := gofeed.NewParser().ParseURL(feed.Url)
	if err != nil {
		return err
	}

	feed.RawTitle = rawFeed.Title
	if feed.Title == "" {
		feed.Title = rawFeed.Title
	}

	for _, item := range rawFeed.Items {
		entry := Entry{
			Date:        *item.PublishedParsed,
			HumanDate:   humanize.Time(*item.PublishedParsed),
			MachineDate: item.PublishedParsed.Format("2006-1-2 15:4"),
			Title:       itemTitle(item.Title, *feed),
			Url:         itemUrl(*item),
		}
		feed.Entries = append(feed.Entries, entry)
	}

	return nil
}

func itemTitle(itemTitle string, feed Feed) (ret string) {
	ret = strings.TrimSpace(strings.TrimPrefix(itemTitle, feed.RawTitle))
	ret = strings.TrimPrefix(ret, "Episode ")
	ret = strings.TrimPrefix(ret, "Ep ")
	for _, prefix := range feed.TrimPrefixes {
		ret = strings.TrimSpace(strings.TrimPrefix(ret, prefix))
	}
	for _, suffix := range feed.TrimSuffixes {
		ret = strings.TrimSpace(strings.TrimSuffix(ret, suffix))
	}
	ret = strings.TrimSpace(ret)
	return
}

func itemUrl(item gofeed.Item) string {
	if len(item.Enclosures) > 0 {
		return item.Enclosures[0].URL
	}
	if strings.Contains(item.Link, "www.youtube.com") {
		return strings.Replace(item.Link, "www.youtube.com", "piped.kavin.rocks", 1) + "&listen=1"
	}
	return item.Link
}
