.PHONY: all
all: public/elm.js public/temp/bundle.js public/apple-touch-icon.png public/favicon.ico

public/temp/bundle.js: index.js
	npm run build

public/elm.js: src/Main.elm
	elm make src/Main.elm --output=public/elm.js --optimize

.PHONY: dev
dev: public/temp/bundle.js
	elm-live src/Main.elm --port=8080 --dir=public/ --open -- --output=public/elm.js --debug

public/favicon.ico public/apple-touch-icon.png:
	convert -font FreeSerif-Bold-Italic \
		-size 1024x1024 xc:'hsl(24,10%,5%)' \
		-kerning 0 -pointsize 840 \
		-undercolor none \
		-fill 'hsl(24,90%,80%)' \
		-annotate +475+800 'P' \
		-fill 'hsl(24,100%,98%)' \
		-annotate +15+800 'N' \
		\( -clone 0 -resize 180x180 -write public/apple-touch-icon.png \) \
		\( -clone 0 -define icon:auto-resize=64,48,32,16 -write public/favicon.ico \) \
		null:

.PHONY: clean
clean: ; rm -vrf public/temp
