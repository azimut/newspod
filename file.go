package main

import (
	"encoding/json"
	"io/ioutil"
)

type JsonFile struct {
	Feeds []Feed `json:"feeds"`
}

func readJsonFeeds(filename string) (feeds []Feed, err error) {
	jsonRawContent, err := ioutil.ReadFile(filename)
	if err != nil {
		return nil, err
	}
	jsonFile := JsonFile{}
	err = json.Unmarshal(jsonRawContent, &jsonFile)
	if err != nil {
		return nil, err
	}
	return jsonFile.Feeds, nil
}
