package main

import (
	"context"
	"database/sql"
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

// persistEtag updates etag value on feeds_metadata table
// assumes there is already an entry for feedid
func persistEtag(db *sql.DB, id int, etag string) error {
	query := `
    UPDATE feeds_metadata
       SET etag = ?
     WHERE feedid = ?
    `
	tx, err := db.Begin()
	if err != nil {
		return err
	}

	stmt_update, err := tx.Prepare(query)
	if err != nil {
		return err
	}
	defer stmt_update.Close()

	_, err = stmt_update.Exec(etag, id)
	if err != nil {
		return err
	}

	err = tx.Commit()
	if err != nil {
		return err
	}
	return nil
}

// persistEtag updates lastmodified value on feeds_metadata table
// assumes there is already an entry for feedid
func persistLastModified(db *sql.DB, id int, lastmodified string) error {
	query := `
    UPDATE feeds_metadata
       SET lastmodified = ?
     WHERE feedid = ?
    `
	tx, err := db.Begin()
	if err != nil {
		return err
	}

	stmt_update, err := tx.Prepare(query)
	if err != nil {
		return err
	}
	defer stmt_update.Close()

	_, err = stmt_update.Exec(lastmodified, id)
	if err != nil {
		return err
	}

	err = tx.Commit()
	if err != nil {
		return err
	}

	return nil
}

func (feed *Feed) UpdateMetadata(db *sql.DB) error {
	res, err := http.Head(feed.Url)
	if err != nil {
		return err
	}

	fmt.Printf("%+v\n", res.Header) // output for debug

	etags, ok := res.Header["Etag"]
	if ok && len(etags) > 0 {
		fmt.Printf("found an etag (%s) for url (%s)\n", etags[0], feed.Url)
		fmt.Println("old etag: ", feed.RawEtag)
		if feed.RawEtag == etags[0] {
			return fmt.Errorf("same etag (%s), skipping feed (%s)", feed.RawEtag, feed.Url)
		} else {
			err = persistEtag(db, feed.RawId, etags[0])
			if err != nil {
				return err
			}
		}
	}

	lastmodified, ok := res.Header["Last-Modified"]
	if ok && len(lastmodified) > 0 {
		fmt.Printf("found an last-modified (%s) for url (%s)\n", lastmodified[0], feed.Url)
		fmt.Println("old last-modified: ", feed.RawLastModified)
		if feed.RawLastModified == lastmodified[0] {
			return fmt.Errorf(
				"same last-modified (%s), skipping feed (%s)",
				feed.RawLastModified,
				feed.Url,
			)
		} else {
			err = persistLastModified(db, feed.RawId, lastmodified[0])
			if err != nil {
				return err
			}
		}
	}

	return nil
}

func (feed *Feed) Fetch() error {

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
