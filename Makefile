public/index.html: main.go feeds.txt layout.html
	mkdir -p public
	rm -f $@
	go run main.go > $@
	tail -50 $@
