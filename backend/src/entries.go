package main

import "time"

type Entry struct {
	Date        time.Time
	Title       string
	Url         string
	Description string
	Content     string
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
