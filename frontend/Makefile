.PHONY: all
all: public/elm.js public/temp/bundle.js public/apple-touch-icon.png public/favicon.ico

public/elm.js: src/Main.elm
	elm make src/Main.elm --output=public/elm.js --optimize

public/temp/bundle.js: index.js
	npm run build

public/favicon.ico public/apple-touch-icon.png:
	convert -size 1024x1024 xc:'hsl(24,10%,5%)' \
		-font FreeSerif-Bold-Italic -kerning 0 -pointsize 840  \
		-fill 'hsl(24, 90%,80%)' -annotate +475+800 'P' \
		-fill 'hsl(24,100%,98%)' -annotate  +15+800 'N' \
		\( +clone -resize 180x180 -write public/apple-touch-icon.png \) \
		\( +clone -define icon:auto-resize=64,48,32,16 -write public/favicon.ico \) \
		null:

.PHONY: dev dev/elm-live dev/webpack dev/css
dev:          ; $(MAKE) -j3 dev/elm-live dev/webpack dev/css
dev/elm-live: ; elm-live src/Main.elm --port=8080 --dir=public/ --open -- --output=public/elm.js --debug
dev/webpack:  ; npx webpack --mode=development --watch
dev/css:      ; echo public/styles.css | entr -rp touch src/Main.elm

.PHONY: clean
clean: ; rm -vrf public/temp
