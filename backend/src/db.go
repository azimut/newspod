package main

import (
	"database/sql"
	"os"

	_ "github.com/mattn/go-sqlite3"
)

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

func insertFeedsAndEntries(db *sql.DB, feeds Feeds) error {
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

	err = insertSearch(db)
	if err != nil {
		return err
	}

	return nil
}

// insertSearch populates `search` table.
// Assumes there are already `entries_content` on the db.
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
