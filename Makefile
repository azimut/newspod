index.html: feeds.txt
	go run main.go | tee index.html
