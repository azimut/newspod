package main

import (
	"database/sql"
	"errors"
	"fmt"
	"os"
	"time"

	_ "github.com/mattn/go-sqlite3"
)

func createTables(db *sql.DB) error {
	initStmt := `
    pragma journal_mode = delete;
    pragma page_size    = 1024;

    create table feeds (
      id     integer not null primary key,
      title  text,
      url    text    not null unique
    ) strict;

    create table feeds_details (
      feedid      integer not null,
      home        text,
      description text,
      language    text,
      image       text,
      author      text,
      foreign key(feedid) references feeds(id)
    ) strict;
    create index feedsdetailsindex on feeds_details(feedid);

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
        title       text,
        description text,
        foreign key(entriesid) references entries(id)
    ) strict;
    create index entriescindex on entries_content(entriesid);

    create virtual table search using fts5(
        title,
        description,
        content='entries_content',
        content_rowid='entriesid'
    );

    CREATE TRIGGER entries_content_ai AFTER INSERT ON entries_content BEGIN
      INSERT INTO search(rowid, title, description) VALUES (new.entriesid, new.title, new.description);
    END;
    CREATE TRIGGER entries_content_ad AFTER DELETE ON entries_content BEGIN
      INSERT INTO search(search, rowid, title, description) VALUES('delete', old.entriesid, old.title, old.description);
    END;
    CREATE TRIGGER entries_content_au AFTER UPDATE ON entries_content BEGIN
      INSERT INTO search(search, rowid, title, description) VALUES('delete', old.entriesid, old.title, old.description);
      INSERT INTO search(rowid, title, description) VALUES (new.entriesid, new.title, new.description);
    END;
    `
	_, err := db.Exec(initStmt)
	if err != nil {
		return err
	}
	return nil
}

func dbOpen(filename, mode string) (db *sql.DB, err error) {
	alreadyExits := true
	_, err = os.Stat(filename)
	if errors.Is(err, os.ErrNotExist) {
		fmt.Println("  [+] database does NOT exits, will create it")
		alreadyExits = false
	}

	db, err = sql.Open("sqlite3", fmt.Sprintf("file:%s?mode=%s", filename, mode))
	if err != nil {
		return nil, err
	}

	if !alreadyExits {
		fmt.Printf("  [+] Creating tables ... ")
		err = createTables(db)
		fmt.Println("DONE")
		if err != nil {
			return nil, err
		}
	}
	return
}

// LoadDB loads bare minum data from a sqlite db, if exits, into Feeds
func LoadDB(filepath string) (Feeds, error) {
	fmt.Printf("[+] Loading `%s`\n", filepath)
	db, err := dbOpen(filepath, "ro")
	if err != nil {
		return nil, err
	}
	defer db.Close()

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
	var feeds Feeds
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
	return feeds, nil
}

func (feeds Feeds) Save(filename string) error {
	fmt.Printf("[+] Saving `%s` ... ", filename)
	db, err := dbOpen(filename, "rwc")
	if err != nil {
		return err
	}
	defer db.Close()

	tx, err := db.Begin()
	if err != nil {
		return err
	}
	stmt_feeds, err := tx.Prepare("insert into feeds(title,url) values(?,?)")
	if err != nil {
		return err
	}
	defer stmt_feeds.Close()
	stmt_feeds_details, err := tx.Prepare(
		"insert into feeds_details(feedid,home,description,language,image,author) values(?,?,?,?,?,?)",
	)
	if err != nil {
		return err
	}
	defer stmt_feeds_details.Close()
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
		"insert into entries_content(entriesid,title,description) values(?,?,?)",
	)
	if err != nil {
		return err
	}
	defer stmt_entry_content.Close()
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
			res, err := stmt_feeds.Exec(feed.Title, feed.Url)
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
			_, err = stmt_feeds_details.Exec(
				effectiveFeedId,
				feed.Home,
				feed.Description,
				feed.Language,
				feed.Image,
				feed.Author,
			)
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
	fmt.Println("DONE")
	return nil
}
