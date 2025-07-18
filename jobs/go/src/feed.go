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

type Address struct {
	From string `json:"from"`
	To   string `json:"to"`
}

type Feed struct {
	Url              string    `json:"url"`
	Title            string    `json:"title"`
	TrimPrefixes     []string  `json:"trim_prefixes"`
	TrimSuffixes     []string  `json:"trim_suffixes"`
	EpisodeBlackList []string  `json:"episode_blacklist"`
	EpisodeWhiteList []string  `json:"episode_whitelist"`
	ContentEndMark   []string  `json:"content_end_mark"`
	ContentExclude   []Address `json:"content_exclude"`
	Tags             []string  `json:"tags"`

	RawId           int
	RawLastEntry    time.Time
	RawLastFetch    time.Time
	RawLastModified string
	RawEtag         string
	NetworkError    bool

	Entries     Entries
	RawTitle    string
	Description string
	Image       string
	Language    string
	Author      string
	Home        string
}

type Feeds []Feed

func (feed *Feed) FetchMetadata() error {

	res, err := http.Head(feed.Url)
	if err != nil {
		feed.NetworkError = true
		return err
	}

	etags, ok := res.Header["Etag"]
	if ok && len(etags) > 0 {
		fmt.Printf(
			"found Etag header (%s), old value (%s)\n",
			etags[0],
			feed.RawEtag,
		)
		if feed.RawEtag == etags[0] {
			return fmt.Errorf("same Etag (%s)", feed.RawEtag)
		}
		feed.RawEtag = etags[0]
	}

	lastmodified, ok := res.Header["Last-Modified"]
	if ok && len(lastmodified) > 0 {
		fmt.Printf(
			"found Last-Modified header (%s), old value (%s)\n",
			lastmodified[0],
			feed.RawLastModified,
		)
		if feed.RawLastModified == lastmodified[0] {
			return fmt.Errorf(
				"same Last-Modified (%s)",
				feed.RawLastModified,
			)
		}
		feed.RawLastModified = lastmodified[0]
	}

	return nil
}

func (feed *Feed) Fetch() error {

	err := feed.FetchMetadata()
	if err != nil {
		fmt.Printf("skipping feed fetch with reason: %v\n", err)
		return nil
	}

	ctx, cancel := context.WithTimeout(context.Background(), time.Second*30)
	defer cancel()

	rawFeed, err := gofeed.NewParser().ParseURLWithContext(feed.Url, ctx)
	if err != nil {
		return err
	}

	html2md := md.NewConverter("", true, nil)

	feed.RawTitle = rawFeed.Title
	if strings.TrimSpace(feed.Title) == "" {
		feed.Title = rawFeed.Title
	}

	feed.Description, err = html2md.ConvertString(rawFeed.Description)
	if err != nil {
		return err
	}
	feed.Language = rawFeed.Language
	if rawFeed.Image != nil {
		feed.Image = rawFeed.Image.URL
	}
	feed.Home = rawFeed.Link
	if len(rawFeed.Authors) > 0 {
		feed.Author = rawFeed.Authors[0].Name
	}

	var keepItem bool
	for _, item := range rawFeed.Items {
		// Process only NEW entries (avoid INSERT attempts)
		if item.PublishedParsed.Before(feed.RawLastEntry) {
			continue
		}

		keepItem = true
		if len(feed.EpisodeWhiteList) > 0 {
			keepItem = false
		}
		for _, word := range feed.EpisodeWhiteList {
			if strings.Contains(item.Title, word) {
				keepItem = true
				break
			}
		}
		for _, word := range feed.EpisodeBlackList {
			if strings.Contains(item.Title, word) {
				keepItem = false
				break
			}
		}
		if !keepItem {
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
		for _, addr := range feed.ContentExclude {
			from_line := -1
			to_line := -1
			new_content := make([]string, 0)
			for nline, line := range strings.Split(entry.Content, "\n") {
				if strings.HasPrefix(line, addr.From) && from_line == -1 {
					from_line = nline
				} else if strings.HasPrefix(line, addr.To) && to_line == -1 {
					to_line = nline
				}
				if (from_line < 0 && to_line < 0) || (from_line >= 0 && to_line >= 0) {
					new_content = append(new_content, line)
				}
			}
			if from_line >= 0 && to_line >= 0 {
				entry.Content = strings.Join(new_content, "\n")
			}
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
	return item.Link
}
