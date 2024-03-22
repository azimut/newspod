public/index.html: src/main.go src/feed.go src/file.go feeds.json layout.html
	mkdir -p public
	rm -f $@
	go run -tags "sqlite_fts5 sqlite_foreign_keys" ./... > $@
	tail -50 $@

.PHONY: clean
clean:
	rm -rf public
