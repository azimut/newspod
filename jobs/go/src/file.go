package main

import (
	"encoding/json"
	"os"
)

type JsonFile struct {
	Feeds []Feed `json:"feeds"`
}

func LoadJson(filename string) (feeds Feeds, err error) {
	jsonRawContent, err := os.ReadFile(filename)
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
