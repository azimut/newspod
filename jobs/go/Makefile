SRCS := $(wildcard src/*.go)

feeds.db: $(SRCS) feeds.json
	go run -tags "sqlite_fts5 sqlite_foreign_keys" ./...
	stat $@

.PHONY: debug
debug:
	cp feeds.json src/
	go build -o main -gcflags "all=-N -l" -tags "sqlite_fts5 sqlite_foreign_keys" src/*.go
