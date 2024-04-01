package main

import "fmt"

func main() {

	feeds, err := readJsonFeeds("feeds.json")
	if err != nil {
		panic(err)
	}

	fmt.Println("Starting RSS feeds fetch...")
	for i := range feeds {
		err := feeds[i].Fetch()
		if err == nil {
			fmt.Printf(
				"[%02d/%02d] success (%s)\n",
				i+1,
				len(feeds),
				feeds[i].Url,
			)
		} else {
			fmt.Printf(
				"[%02d/%02d] failure (%s) with error (%v)\n",
				i+1,
				len(feeds),
				feeds[i].Url,
				err,
			)
		}
	}

	feeds.Sort()

	err = feeds.Save()
	if err != nil {
		panic(err)
	}
}
