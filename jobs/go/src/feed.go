package main

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"time"

	md "github.com/JohannesKaufmann/html-to-markdown"
	"github.com/adrg/strutil"
	"github.com/adrg/strutil/metrics"
	"github.com/mmcdole/gofeed"
)

type Feed struct {
	Url            string   `json:"url"`
	Title          string   `json:"title"`
	TrimPrefixes   []string `json:"trim_prefixes"`
	TrimSuffixes   []string `json:"trim_suffixes"`
	ContentEndMark []string `json:"content_end_mark"`

	RawId           int
	RawEtag         string
	RawLastModified string
	RawLastFetch    time.Time

	Entries     Entries
	RawTitle    string
	Description string
}

func (feed *Feed) FetchMetadata() (err error) {

	res, err := http.Head(feed.Url)
	if err != nil {
		return err
	}

	etags, ok := res.Header["Etag"]
	if ok && len(etags) > 0 {
		fmt.Printf(
			"found an etag (%s) for url (%s), old value (%s)\n",
			etags[0],
			feed.Url,
			feed.RawEtag,
		)
		if feed.RawEtag == etags[0] {
			return fmt.Errorf("same etag (%s), skipping feed (%s)", feed.RawEtag, feed.Url)
		}
		feed.RawEtag = etags[0]
	}

	lastmodified, ok := res.Header["Last-Modified"]
	if ok && len(lastmodified) > 0 {
		fmt.Printf(
			"found an last-modified (%s) for url (%s), old value (%s)\n",
			lastmodified[0],
			feed.Url,
			feed.RawLastModified,
		)
		if feed.RawLastModified == lastmodified[0] {
			return fmt.Errorf(
				"same last-modified (%s), skipping feed (%s)",
				feed.RawLastModified,
				feed.Url,
			)
		}
		feed.RawLastModified = lastmodified[0]
	}

	return
}

func (feed *Feed) Fetch() error {

	err := feed.FetchMetadata()
	if err != nil {
		fmt.Printf("skipping feed fetch with reason (%v)\n", err)
		return nil
	}

	ctx, cancel := context.WithTimeout(context.Background(), time.Second*30)
	defer cancel()

	rawFeed, err := gofeed.NewParser().ParseURLWithContext(feed.Url, ctx)
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
		// Process only NEW entries, after last fetch (avoid INSERT attempts)
		if item.PublishedParsed.Before(feed.RawLastFetch) {
			continue
		}
		entry := Entry{
			Date:        *item.PublishedParsed,
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
