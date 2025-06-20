.PHONY: all
all: frontend/public/feeds.db
	cd frontend/ && npm install && make

jobs/go/feeds.db:
	cd jobs/go/ && make

frontend/public/feeds.db: jobs/go/feeds.db
	echo 'PRAGMA page_size=1024; VACUUM' | sqlite3 $@
	sqlite3 $< .dump | sqlite3 $@
	echo "INSERT INTO search(search) VALUES('optimize'); VACUUM" | sqlite3 $@

.PHONY: slim
slim:; echo '{"feeds":[{"url":"'$(shell jq -r '.feeds[].url' jobs/go/feeds.json | shuf -n1)'"}]}' > jobs/go/feeds.json

.PHONY: cloc
cloc:; cloc . --vcs=git --exclude-lang=JSON
