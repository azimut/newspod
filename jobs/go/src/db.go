package main

import (
	"database/sql"
	"errors"
	"fmt"
	"os"
	"slices"
	"time"

	_ "github.com/mattn/go-sqlite3"
)

func createTables(db *sql.DB) error {
	initStmt := `
    CREATE TABLE feeds (
      id     integer not null primary key,
      title  text,
      url    text    not null unique
    ) strict;

    CREATE TABLE feeds_details (
      feedid      integer not null,
      home        text,
      description text,
      language    text,
      image       text,
      author      text,
      foreign key(feedid) references feeds(id)
    ) strict;
    CREATE INDEX feedsdetailsindex ON feeds_details(feedid);

    CREATE TABLE feeds_metadata (
      feedid       integer not null,
      lastentry    integer not null default 0,
      lastfetch    integer not null default 0,
      lastmodified text    not null default "",
      etag         text    not null default "",
      foreign key(feedid) references feeds(id)
    ) strict;
    CREATE INDEX feedsmetaindex ON feeds_metadata(feedid);

    CREATE TABLE entries (
        id          integer not null primary key,
        feedid      integer not null,
        datemillis  integer not null,
        title       text,
        url         text    not null unique,
        foreign key(feedid) references feeds(id)
    ) strict;
    CREATE INDEX entriesindex ON entries(feedid);

    CREATE TABLE entries_content (
        entriesid   integer not null,
        title       text,
        description text,
        foreign key(entriesid) references entries(id)
    ) strict;
    CREATE INDEX entriescindex ON entries_content(entriesid);

    CREATE TABLE tags (
      id     integer not null primary key,
      name   text    not null unique
    ) strict;

    CREATE TABLE feed_tags (
      feedid integer not null,
      tagid  integer not null,
      foreign key(feedid) references feeds(id),
      foreign key(tagid)  references tags(id)
    ) strict;

    CREATE VIRTUAL TABLE search USING fts5(
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

func dbOpen(filename, mode string) (*sql.DB, error) {
	var dataSource string
	var alreadyExits bool
	_, err := os.Stat(filename)
	if errors.Is(err, os.ErrNotExist) {
		fmt.Println("  [+] database does NOT exits, will create it")
		dataSource = filename
	} else {
		dataSource = fmt.Sprintf("file:%s?mode=%s", filename, mode)
		alreadyExits = true
	}

	db, err := sql.Open("sqlite3", dataSource)
	if err != nil {
		return nil, err
	}

	_, err = db.Exec(`
        pragma journal_mode = delete;
        pragma page_size    = 1024;`)
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
	return db, nil
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
             feeds_metadata.lastentry,
             feeds_metadata.lastfetch,
             feeds_metadata.lastmodified,
             feeds_metadata.etag
        FROM feeds
        JOIN feeds_metadata ON feeds.id=feeds_metadata.feedid
    `)
	if err != nil {
		return nil, err
	}

	var id, lastfetch, lastentry int
	var url, lastmodified, etag string
	var feeds Feeds
	for rows.Next() {
		err = rows.Scan(&id, &url, &lastentry, &lastfetch, &lastmodified, &etag)
		if err != nil {
			return nil, err
		}
		feed := Feed{
			Url:             url,
			RawId:           id,
			RawEtag:         etag,
			RawLastFetch:    time.Unix(int64(lastfetch), 0),
			RawLastEntry:    time.Unix(int64(lastentry), 0),
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

	init_feeds, err := tx.Prepare(
		"INSERT INTO feeds(title,url) VALUES(?,?)")
	if err != nil {
		return err
	}
	defer init_feeds.Close()

	init_feeds_details, err := tx.Prepare(
		"INSERT INTO feeds_details(feedid,home,description,language,image,author) VALUES(?,?,?,?,?,?)",
	)
	if err != nil {
		return err
	}
	defer init_feeds_details.Close()

	init_feeds_metadata, err := tx.Prepare(
		"INSERT INTO feeds_metadata(feedid) VALUES(?)")
	if err != nil {
		return err
	}
	defer init_feeds_metadata.Close()

	insert_entries, err := tx.Prepare(
		"INSERT INTO entries(feedid,datemillis,title,url) VALUES(?,?,?,?)")
	if err != nil {
		return err
	}
	defer insert_entries.Close()

	insert_entries_content, err := tx.Prepare(
		"INSERT INTO entries_content(entriesid,title,description) VALUES(?,?,?)")
	if err != nil {
		return err
	}
	defer insert_entries_content.Close()

	update_feeds_metadata, err := tx.Prepare(`
    UPDATE feeds_metadata
       SET lastfetch = strftime('%s'), lastmodified = ?, etag = ?
     WHERE feedid = ?`)
	if err != nil {
		return err
	}
	defer update_feeds_metadata.Close()

	update_feeds_metadata_lastentry, err := tx.Prepare(`
    UPDATE feeds_metadata
       SET lastentry = ?
     WHERE feedid = ? AND lastentry < ?`)
	if err != nil {
		return err
	}
	defer update_feeds_metadata_lastentry.Close()

	update_feeds_title, err := tx.Prepare(
		`UPDATE feeds SET title = ? WHERE id = ? AND title <> ?`)
	if err != nil {
		return err
	}
	defer update_feeds_title.Close()

	for fid := range feeds {
		feed := feeds[fid]
		effectiveFeedId := feed.RawId
		if effectiveFeedId == 0 { // first time seen
			res, err := init_feeds.Exec(feed.Title, feed.Url)
			if err != nil {
				return err
			}
			tmp, err := res.LastInsertId()
			if err != nil {
				return err
			}
			effectiveFeedId = int(tmp)
			feed.RawId = int(tmp)
			_, err = init_feeds_metadata.Exec(effectiveFeedId)
			if err != nil {
				return err
			}
			_, err = init_feeds_details.Exec(
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

		if feed.Title != "" {
			_, err = update_feeds_title.Exec(feed.Title, effectiveFeedId, feed.Title)
			if err != nil {
				return err
			}
		}

		if feed.NetworkError {
			continue
		}

		_, err = update_feeds_metadata.Exec(feed.RawLastModified, feed.RawEtag, effectiveFeedId)
		if err != nil {
			return err
		}

		for _, entry := range feed.Entries {
			res, err := insert_entries.Exec(
				effectiveFeedId,
				entry.Date.UnixMilli(),
				entry.Title,
				entry.Url,
			)
			if err != nil {
				continue // skip entries_content add
			}
			lastEntryId, err := res.LastInsertId()
			if err != nil {
				return err
			}
			_, err = insert_entries_content.Exec(
				lastEntryId,
				entry.Title,
				entry.Content,
			)
			if err != nil {
				return err
			}
			_, err = update_feeds_metadata_lastentry.Exec(
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

	err = feeds.db_insert_tags(db)
	if err != nil {
		return err
	}

	sqlStmt := `
    INSERT INTO search(search) VALUES('optimize');
	VACUUM;`
	_, err = db.Exec(sqlStmt)
	if err != nil {
		return err
	}
	fmt.Println("DONE")
	return nil
}

func (feeds Feeds) db_insert_tags(db *sql.DB) error {
	fmt.Printf("[+] Inserting feed tags ... ")
	err := db_delete_tags(db)
	if err != nil {
		return err
	}
	var unique_tags []string
	var next_tag_id int
	for _, feed := range feeds {
		for _, tag_name := range feed.Tags {
			var tag_id int
			if slices.Contains(unique_tags, tag_name) {
				tag_id = slices.Index(unique_tags, tag_name)
			} else {
				tag_id = next_tag_id
				unique_tags = append(unique_tags, tag_name)
				next_tag_id++
				err = db_insert_tag(db, tag_id, tag_name)
				if err != nil {
					return err
				}
			}
			err = db_insert_feed_tag(db, feed.RawId, tag_id) // assumes feed.RawId has a valid value
			if err != nil {
				return err
			}
		}
	}
	fmt.Println("DONE")
	fmt.Printf("%+v\n", unique_tags) // output for debug
	return nil
}

func db_delete_tags(db *sql.DB) error {
	_, err := db.Exec("DELETE FROM feed_tags; DELETE FROM tags;")
	return err
}
func db_insert_tag(db *sql.DB, id int, name string) error {
	_, err := db.Exec("INSERT INTO tags(id, name) VALUES(?,?)", id, name)
	return err
}
func db_insert_feed_tag(db *sql.DB, feed_id, tag_id int) error {
	_, err := db.Exec("INSERT INTO feed_tags(feedid, tagid) VALUES(?,?)", feed_id, tag_id)
	return err
}
