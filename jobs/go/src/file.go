package main

import (
	"encoding/json"
	"fmt"
	"os"
)

type JsonFile struct {
	Feeds []Feed `json:"feeds"`
}

func LoadJson(filename string) (feeds Feeds, err error) {
	fmt.Printf("[+] Loading `%s` ... ", filename)
	jsonRawContent, err := os.ReadFile(filename)
	if err != nil {
		return nil, err
	}
	jsonFile := JsonFile{}
	err = json.Unmarshal(jsonRawContent, &jsonFile)
	if err != nil {
		return nil, err
	}
	fmt.Println("DONE")
	return jsonFile.Feeds, nil
}
