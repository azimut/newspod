.PHONY: all
all:
	cd jobs/go/                      && make
	cd jobs/python/                  && python3 main.py
	cd jobs/python/generate_startup/ && python3 main.py
	cp jobs/go/feeds.db                                frontend/public/feeds.db.tar.gz
	cp jobs/python/generate_startup/feeds.startup.json frontend/public/
	cd frontend/                     && npm install && make

.PHONY: slim
slim:; echo '{"feeds":[{"url":"'$(shell jq -r '.feeds[].url' jobs/go/feeds.json | shuf -n1)'"}]}' > jobs/go/feeds.json

.PHONY: cloc
cloc:; cloc . --vcs=git --exclude-lang=JSON
