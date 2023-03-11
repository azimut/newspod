index.html: main.go feeds.txt layout.html
	go run main.go | tee index.html
