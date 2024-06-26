package main

import (
	"database/sql"
	"errors"
	"fmt"
	"os"
	"time"

	_ "github.com/mattn/go-sqlite3"
)

func initTables(db *sql.DB) error {
	initStmt := `
    pragma journal_mode = delete;
    pragma page_size    = 1024;

    create table feeds (
        id          integer not null primary key,
        title       text,
        url         text    not null unique,
        description text
    ) strict;

    create table feeds_metadata (
      feedid       integer not null,
      lastentry    integer not null default 0,
      lastfetch    integer not null default 0,
      lastmodified text    not null default "",
      etag         text    not null default "",
      foreign key(feedid) references feeds(id)
    ) strict;
    create index feedsmetaindex on feeds_metadata(feedid);

    create table entries (
        id          integer not null primary key,
        feedid      integer not null,
        datemillis  integer not null,
        title       text,
        url         text    not null unique,
        foreign key(feedid) references feeds(id)
    ) strict;
    create index entriesindex on entries(feedid);

    create table entries_content (
        entriesid   integer not null,
        content     text,
        foreign key(entriesid) references entries(id)
    ) strict;
    create index entriescindex on entries_content(entriesid);

    create virtual table search using fts5(
        entriesid unindexed,
        title,
        content
    );
    `
	_, err := db.Exec(initStmt)
	if err != nil {
		return err
	}

	return nil
}

// LoadDb loads bare minum data from a sqlite db, if exits, into Feeds
func LoadDb(db *sql.DB) (feeds Feeds, err error) {
	rows, err := db.Query(`
      SELECT feeds.id,
             feeds.url,
             feeds_metadata.lastfetch,
             feeds_metadata.lastmodified,
             feeds_metadata.etag
        FROM feeds
        JOIN feeds_metadata ON feeds.id=feeds_metadata.feedid
    `)
	if err != nil {
		return nil, err
	}

	var id, lastfetch int
	var url, lastmodified, etag string
	for rows.Next() {
		err = rows.Scan(&id, &url, &lastfetch, &lastmodified, &etag)
		if err != nil {
			return nil, err
		}
		feed := Feed{
			Url:             url,
			RawId:           id,
			RawEtag:         etag,
			RawLastFetch:    time.Unix(int64(lastfetch), 0),
			RawLastModified: lastmodified,
		}
		feeds = append(feeds, feed)
	}

	return
}

func InitDB(dbname string) (db *sql.DB, err error) {
	alreadyExits := true
	_, err = os.Stat(dbname)
	if errors.Is(err, os.ErrNotExist) {
		fmt.Printf("db (%s) does not exits, creating\n", dbname)
		alreadyExits = false
	}

	db, err = sql.Open("sqlite3", dbname)
	if err != nil {
		return nil, err
	}

	if !alreadyExits {
		err = initTables(db)
		if err != nil {
			return nil, err
		}
	}
	return
}

func (feeds Feeds) Save(db *sql.DB) error {
	fmt.Println("starting db save...")
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	stmt_feeds, err := tx.Prepare("insert into feeds(title,url,description) values(?,?,?)")
	if err != nil {
		return err
	}
	defer stmt_feeds.Close()
	stmt_feeds_meta_init, err := tx.Prepare("insert into feeds_metadata(feedid) values(?)")
	if err != nil {
		return err
	}
	defer stmt_feeds_meta_init.Close()
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
	stmt_entry_search, err := tx.Prepare(
		"INSERT INTO search(entriesid,title,content) VALUES (?,?,?)",
	)
	if err != nil {
		return err
	}
	defer stmt_entry_search.Close()
	stmt_feeds_meta_update, err := tx.Prepare(`
    UPDATE feeds_metadata
       SET lastfetch = strftime('%s'), lastmodified = ?, etag = ?
     WHERE feedid = ?
    `)
	if err != nil {
		return err
	}
	defer stmt_feeds_meta_update.Close()
	stmt_feeds_meta_lastentry, err := tx.Prepare(`
    UPDATE feeds_metadata
       SET lastentry = ?
     WHERE feedid = ? AND lastentry < ?
    `)
	if err != nil {
		return err
	}
	defer stmt_feeds_meta_lastentry.Close()

	for _, feed := range feeds {
		effectiveFeedId := feed.RawId
		if feed.RawLastFetch.IsZero() { // first time seen
			res, err := stmt_feeds.Exec(feed.Title, feed.Url, feed.Description)
			if err != nil {
				return err
			}
			tmp, err := res.LastInsertId()
			if err != nil {
				return err
			}
			effectiveFeedId = int(tmp)
			_, err = stmt_feeds_meta_init.Exec(effectiveFeedId)
			if err != nil {
				return err
			}
		}

		_, err = stmt_feeds_meta_update.Exec(feed.RawLastModified, feed.RawEtag, effectiveFeedId)
		if err != nil {
			return err
		}

		for _, entry := range feed.Entries {
			// entries
			res, err := stmt_entry.Exec(
				effectiveFeedId,
				entry.Date.UnixMilli(),
				entry.Title,
				entry.Url,
			)
			if err != nil {
				continue // skip content add
			}
			// entries_content
			lastEntryId, err := res.LastInsertId()
			if err != nil {
				return err
			}
			_, err = stmt_entry_content.Exec(
				lastEntryId,
				entry.Content,
			)
			if err != nil {
				return err
			}
			_, err = stmt_entry_search.Exec(
				lastEntryId,
				entry.Title,
				entry.Content,
			)
			if err != nil {
				return err
			}
			_, err = stmt_feeds_meta_lastentry.Exec(
				entry.Date.UnixMilli(),
				effectiveFeedId,
				entry.Date.UnixMilli(),
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

	sqlStmt := `
	insert into search(search) values('optimize');
	vacuum;`
	_, err = db.Exec(sqlStmt)
	if err != nil {
		return err
	}
	fmt.Println("...save done!")
	return nil
}
