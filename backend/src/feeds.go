package main

import (
	"sort"
	"strings"

	md "github.com/JohannesKaufmann/html-to-markdown"
	"github.com/adrg/strutil"
	"github.com/adrg/strutil/metrics"
	"github.com/dustin/go-humanize"
	"github.com/mmcdole/gofeed"
)

const DB_NAME = "./feeds.db"

type Feed struct {
	Entries        Entries
	RawTitle       string
	Title          string   `json:"title"`
	TrimPrefixes   []string `json:"trim_prefixes"`
	TrimSuffixes   []string `json:"trim_suffixes"`
	ContentEndMark []string `json:"content_end_mark"`
	Description    string
	Url            string `json:"url"`
}

type Feeds []Feed

func (a Feeds) Less(i, j int) bool {
	if len(a[i].Entries) == 0 {
		return false
	}
	if len(a[j].Entries) == 0 {
		return true
	}
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

func (feeds Feeds) Sort() {
	for i := 0; i < len(feeds); i++ {
		sort.Sort(feeds[i].Entries)
	}
	sort.Sort(feeds)
}

func (feeds Feeds) Save() error {
	db, err := initDb()
	if err != nil {
		return err
	}
	defer db.Close()
	err = insertFeedsAndEntries(db, feeds)
	if err != nil {
		return err
	}
	return nil
}

func (feed *Feed) Fetch() error {
	rawFeed, err := gofeed.NewParser().ParseURL(feed.Url)
	if err != nil {
		return err
	}

	feed.Description = rawFeed.Description
	feed.RawTitle = rawFeed.Title
	if strings.TrimSpace(feed.Title) == "" {
		feed.Title = rawFeed.Title
	}

	html2md := md.NewConverter("", true, nil)

	for _, item := range rawFeed.Items {
		entry := Entry{
			Date:        *item.PublishedParsed,
			HumanDate:   humanize.Time(*item.PublishedParsed),
			MachineDate: item.PublishedParsed.Format("2006-01-02 15:04:03"),
			Title:       itemTitle(item.Title, *feed),
			Url:         itemUrl(*item),
			Description: item.Description,
			Content:     item.Content,
		}
		if item.Content == item.Description { // prefer content
			entry.Description = ""
		}
		if item.Description != "" && item.Content == "" { // prefer content (2)
			entry.Content = item.Description
		}
		if entry.Description == "" && item.ITunesExt != nil && item.ITunesExt.Subtitle != "" {
			entry.Description = item.ITunesExt.Subtitle
		}
		if entry.Content == "" && item.ITunesExt != nil && item.ITunesExt.Summary != "" {
			entry.Content = item.ITunesExt.Summary
		}
		entry.Description, err = html2md.ConvertString(entry.Description)
		if err != nil {
			return err
		}
		entry.Content, err = html2md.ConvertString(entry.Content)
		if err != nil {
			return err
		}
		metric := strutil.Similarity(
			entry.Description,
			entry.Content,
			metrics.NewHamming(),
		)
		if metric > 0.1 { // prefer content (3)
			entry.Description = ""
		}
		for _, mark := range feed.ContentEndMark {
			before, _, _ := strings.Cut(entry.Content, mark)
			entry.Content = before
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
