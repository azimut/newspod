SRCS := $(wildcard src/*.go)

feeds.db: $(SRCS) feeds.json
	go run -tags "sqlite_fts5 sqlite_foreign_keys" ./...
