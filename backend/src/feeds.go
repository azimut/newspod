package main

import (
	"sort"
)

const DB_NAME = "./feeds.db"

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
