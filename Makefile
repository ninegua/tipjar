OBJ_DIR=.dfx/ic/canisters
DIST_DIR=./dist
IMAGES_SRC=$(wildcard src/tipjar_assets/assets/*.png) $(wildcard src/tipjar_assets/assets/*/*/*.png) $(wildcard src/tipjar_assets/assets/*.ico)
ASSETS_SRC=$(wildcard src/tipjar_assets/src/*.html) $(wildcard src/tipjar_assets/src/*.js) src/tipjar_assets/assets/tipjar.webmanifest src/tipjar_assets/assets/faq.html
MOTOKO_SRC=$(wildcard src/tipjar/*.mo) 
SRC=$(MOTOKO_SRC) $(ASSETS_SRC) $(IMAGES_SRC)

$(OBJ_DIR)/tipjar/tipjar.wasm $(OBJ_DIR)/tipjar/tipjar.did $(DIST_DIR)/index.html $(DIST_DIR)/index.js &: $(SRC)
	dfx build --network=ic

upgrade: upgrade_backend upgrade_frontend

upgrade_backend: $(OBJ_DIR)/tipjar/tipjar.wasm $(OBJ_DIR)/tipjar/tipjar.did
	dfx canister --network=ic stop tipjar && \
	dfx canister --network=ic install --mode=upgrade tipjar && \
	dfx canister --network=ic start tipjar

upgrade_frontend: $(DIST_DIR)/index.html $(DIST_DIR)/index.js
	dfx canister --network=ic install --mode=upgrade tipjar_assets

src/tipjar_assets/assets/faq.html: FAQ.md
	tail -n"$$(($$(wc -l FAQ.md|cut -d\  -f1) - 1))" $< | \
		pandoc --css=https://cdn.simplecss.org/simple.min.css --toc --toc-depth=6 \
		--template=template.html -f markdown -t html --shift-heading-level-by=3 > $@

clean:
	rm src/tipjar_assets/assets/faq.html

.PHONY: clean upgrade upgrade_backend upgrade_frontend


