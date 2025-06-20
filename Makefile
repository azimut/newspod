.PHONY: all
all: frontend/public/feeds.db
	cd jobs/go/ && make
	cd frontend/ && npm install && make

frontend/public/feeds.db: jobs/go/feeds.db
	sqlite3 $< .dump | sqlite3 $@

.PHONY: slim
slim:; echo '{"feeds":[{"url":"'$(shell jq -r '.feeds[].url' jobs/go/feeds.json | shuf -n1)'"}]}' > jobs/go/feeds.json

.PHONY: cloc
cloc:; cloc . --vcs=git --exclude-lang=JSON
