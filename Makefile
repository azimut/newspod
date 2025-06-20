.PHONY: all
all:
	cd jobs/go/ && make
	sqlite3 jobs/go/feeds.db .dump | sqlite3 frontend/public/feeds.db
	cd frontend/ && npm install && make

.PHONY: slim
slim:; echo '{"feeds":[{"url":"'$(shell jq -r '.feeds[].url' jobs/go/feeds.json | shuf -n1)'"}]}' > jobs/go/feeds.json

.PHONY: cloc
cloc:; cloc . --vcs=git --exclude-lang=JSON
