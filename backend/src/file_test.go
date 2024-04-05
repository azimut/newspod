package main

import (
	"fmt"
	"testing"
)

var testFile = "./testdata/1.json"

func TestReadJsonFeeds(t *testing.T) {
	feeds, err := LoadJson(testFile)
	if err != nil {
		t.Errorf("could not parse file `%s`, %v", testFile, err)
	}
	if len(feeds) != 1 {
		t.Errorf("got %d want %d", len(feeds), 1)
	}
	fmt.Println(feeds)
}
