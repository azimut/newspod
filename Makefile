.PHONY: all
all:
	cd backend/ && make
	cp backend/feeds.db frontend/public/
	cd frontend/ && npm install && make

.PHONY: cloc
cloc:; cloc . --vcs=git --exclude-lang=JSON
