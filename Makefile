index.html: feeds.txt layout.html
	go run main.go | tee index.html
