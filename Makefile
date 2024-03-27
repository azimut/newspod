.PHONY: all
all:
	cd backend/ && make
	cp backend/feeds.db frontend/public/
	cd frontend/ && npm install && make

.PHONY: slim
slim:; echo '{"feeds":[{"url":"'$(shell jq -r '.feeds | .[] | .url' backend/feeds.json | shuf -n1)'"}]}' > backend/feeds.json

.PHONY: cloc
cloc:; cloc . --vcs=git --exclude-lang=JSON
