.PHONY: all
all:
	cd backend/ && make
	cp backend/feeds.db frontend/public/
	cd frontend/ && make

.PHONY: cloc
cloc:; cloc . --vcs=git --exclude-lang=JSON
