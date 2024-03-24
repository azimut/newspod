.PHONY: all
all: public/elm.js public/temp/bundle.js

public/temp/bundle.js: index.js
	npm run build

public/elm.js: src/Main.elm
	elm make src/Main.elm --output=public/elm.js

.PHONY: dev
dev:
	elm-live src/Main.elm --port=8080 --dir=public/ --open -- --output=public/elm.js --debug
