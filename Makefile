public/index.html: main.go feed.go file.go feeds.json layout.html
	mkdir -p public
	rm -f $@
	go run . > $@
	tail -50 $@

.PHONY: clean
clean:
	rm -rf public
