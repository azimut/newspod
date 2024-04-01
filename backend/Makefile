SRCS := src/main.go src/feeds.go src/db.go src/entries.go src/file.go

feeds.db: $(SRCS) feeds.json
	go run -tags "sqlite_fts5 sqlite_foreign_keys" ./...
