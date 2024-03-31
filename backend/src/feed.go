package main

import (
	"database/sql"
	"os"
	"sort"
	"strings"
	"time"

	md "github.com/JohannesKaufmann/html-to-markdown"
	"github.com/adrg/strutil"
	"github.com/adrg/strutil/metrics"
	"github.com/dustin/go-humanize"
	_ "github.com/mattn/go-sqlite3"
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

type Entry struct {
	Date        time.Time
	HumanDate   string
	MachineDate string
	Title       string
	Url         string
	Description string
	Content     string
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

type Entries []Entry

func (a Entries) Len() int {
	return len(a)
}

func (a Entries) Less(i, j int) bool {
	iDate := a[i].Date
	jDate := a[j].Date
	return iDate.After(jDate)
}

func (a Entries) Swap(i, j int) {
	a[i], a[j] = a[j], a[i]
}

func (feeds Feeds) Sort() {
	for i := 0; i < len(feeds); i++ {
		sort.Sort(feeds[i].Entries)
	}
	sort.Sort(feeds)
}

func initDb() (*sql.DB, error) {
	os.Remove(DB_NAME)

	db, err := sql.Open("sqlite3", DB_NAME)
	if err != nil {
		return nil, err
	}

	initStmt := `
    pragma journal_mode = delete;
    pragma page_size = 1024;

    create table feeds (
        id          integer not null primary key,
        title       text,
        url         text,
        description text
    );

    create table entries (
        id          integer not null primary key,
        feedid      integer not null,
        datemillis  integer not null,
        title       text,
        content     text,
        url         text,
        foreign key(feedid) references feeds(id)
    );
    create index entriesindex on entries(feedid);

    create table entries_content (
        entriesid   integer not null,
        content     text,
        foreign key(entriesid) references entries(id)
    );
    create index entriescindex on entries_content(entriesid);

    create virtual table search using fts5(
        entriesid unindexed,
        content
    );
    `
	_, err = db.Exec(initStmt)
	if err != nil {
		return nil, err
	}

	return db, nil
}

func insertSearch(db *sql.DB) error {
	sqlStmt := `
    insert into search
    select entriesid,content
      from entries_content;
    insert into search(search) values('optimize');
    vacuum;
    `
	_, err := db.Exec(sqlStmt)
	if err != nil {
		return err
	}
	return nil
}

func insertFeeds(db *sql.DB, feeds Feeds) error {
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	stmt_feeds, err := tx.Prepare("insert into feeds(id,title,url,description) values(?,?,?,?)")
	if err != nil {
		return err
	}
	defer stmt_feeds.Close()
	stmt_entry, err := tx.Prepare(
		"insert into entries(feedid,datemillis,title,url) values(?,?,?,?)",
	)
	if err != nil {
		return err
	}
	defer stmt_entry.Close()
	stmt_entry_content, err := tx.Prepare(
		"insert into entries_content(entriesid,content) values(?,?)",
	)
	if err != nil {
		return err
	}
	defer stmt_entry_content.Close()
	for feedid, feed := range feeds {
		_, err = stmt_feeds.Exec(feedid, feed.Title, feed.Url, feed.Description)
		if err != nil {
			return err
		}
		for _, entry := range feed.Entries {
			// entries
			res, err := stmt_entry.Exec(
				feedid,
				entry.Date.UnixMilli(),
				entry.Title,
				entry.Url,
			)
			if err != nil {
				return err
			}
			// entries_content
			entryid, err := res.LastInsertId()
			if err != nil {
				return err
			}
			_, err = stmt_entry_content.Exec(
				entryid,
				entry.Content,
			)
			if err != nil {
				return err
			}
		}
	}
	err = tx.Commit()
	if err != nil {
		return err
	}

	return nil
}

func (feeds Feeds) Save() error {
	db, err := initDb()
	if err != nil {
		return err
	}
	defer db.Close()

	err = insertFeeds(db, feeds)
	if err != nil {
		return err
	}

	err = insertSearch(db)
	if err != nil {
		return err
	}

	return nil
}

func (feed *Feed) fetch() error {
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
