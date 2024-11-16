OBJ_DIR=.dfx/ic/canisters
DIST_DIR=./dist
IMAGES_SRC=$(wildcard src/tipjar_assets/assets/*.png) $(wildcard src/tipjar_assets/assets/*/*/*.png) $(wildcard src/tipjar_assets/assets/*.ico)
ASSETS_SRC=$(wildcard src/tipjar_assets/src/*.html) $(wildcard src/tipjar_assets/src/*.js) src/tipjar_assets/assets/tipjar.webmanifest src/tipjar_assets/assets/faq.html
MOTOKO_SRC=$(wildcard src/tipjar/*.mo) 
SRC=$(MOTOKO_SRC) $(ASSETS_SRC) $(IMAGES_SRC)
IC_VERSION=a17247bd86c7aa4e87742bf74d108614580f216d

deploy: download
	dfx deploy

download: src/blackhole/blackhole.did src/blackhole/blackhole-opt.wasm \
	src/ledger/ledger.did src/cmc/cmc.did \
	src/cycles_ledger/cycles-ledger.did src/cycles_ledger/cycles-ledger.wasm.gz

src/blackhole/blackhole.did:
	curl -Lo $@ https://github.com/ninegua/ic-blackhole/releases/download/0.0.0/blackhole.did

src/blackhole/blackhole-opt.wasm:
	curl -Lo $@ https://github.com/ninegua/ic-blackhole/releases/download/0.0.0/blackhole-opt.wasm

src/cycles_ledger/cycles-ledger.did:
	curl -Lo $@ https://github.com/dfinity/cycles-ledger/releases/download/cycles-ledger-v1.0.2/cycles-ledger.did
	sed -e 's/vec nat8/blob/' -i $@

src/cycles_ledger/cycles-ledger.wasm.gz:
	curl -Lo $@ https://github.com/dfinity/cycles-ledger/releases/download/cycles-ledger-v1.0.2/cycles-ledger.wasm.gz

src/ledger/ledger.did:
	curl -Lo $@ https://raw.githubusercontent.com/dfinity/ic/$(IC_VERSION)/rs/rosetta-api/icp_ledger/ledger.did

src/cmc/cmc.did:
	curl -Lo $@ https://raw.githubusercontent.com/dfinity/ic/$(IC_VERSION)/rs/nns/cmc/cmc.did

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

distclean: clean
	rm src/blackhole/blackhole.did src/blackhole/blackhole-opt.wasm \
		src/ledger/ledger.did src/cmc/cmc.did

.PHONY: clean distclean upgrade upgrade_backend upgrade_frontend download deploy
