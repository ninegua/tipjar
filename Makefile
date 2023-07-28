OBJ_DIR=.dfx/ic/canisters
DIST_DIR=./dist
IMAGES_SRC=$(wildcard src/tipjar_assets/assets/*.png) $(wildcard src/tipjar_assets/assets/*/*/*.png) $(wildcard src/tipjar_assets/assets/*.ico)
ASSETS_SRC=$(wildcard src/tipjar_assets/src/*.html) $(wildcard src/tipjar_assets/src/*.js) src/tipjar_assets/assets/tipjar.webmanifest src/tipjar_assets/assets/faq.html
MOTOKO_SRC=$(wildcard src/tipjar/*.mo) 
SRC=$(MOTOKO_SRC) $(ASSETS_SRC) $(IMAGES_SRC)
IC_VERSION=a17247bd86c7aa4e87742bf74d108614580f216d

deploy: download
	cd src/ledger && rm -f ledger.did && ln -s ledger.private.did ledger.did
	dfx canister create ledger
	dfx deploy --argument '(record {send_whitelist=vec{}; minting_account="051b05839339f89053454a4b9865ea0452a4bffe2b1cd41f4982bad10c1e637c"; transaction_window = null; max_message_size_bytes = null; archive_options = null; initial_values = vec {record{"9bf916c86e344b8a0aaac73271ae0612e8212d0bd59e30db38281982f46d3d2b"; record {e8s=100_000_000_000}}};})' ledger
	cd src/ledger && rm -f ledger.did && ln -s ledger.public.did ledger.did
	dfx deploy

download: src/blackhole/blackhole.did src/blackhole/blackhole-opt.wasm \
	src/ledger/ledger.wasm src/ledger/ledger.private.did src/ledger/ledger.public.did

src/blackhole/blackhole.did:
	curl -Lo $@ https://github.com/ninegua/ic-blackhole/releases/download/0.0.0/blackhole.did

src/blackhole/blackhole-opt.wasm:
	curl -Lo $@ https://github.com/ninegua/ic-blackhole/releases/download/0.0.0/blackhole-opt.wasm

src/ledger/ledger.wasm: src/ledger/ledger.wasm.gz
	gunzip -fk $<

src/ledger/ledger.wasm.gz:
	curl -Lo $@ https://download.dfinity.systems/ic/$(IC_VERSION)/canisters/ledger-canister_notify-method.wasm.gz

src/cmc/cycles-minting-canister.wasm: src/cmc/cycles-minting-canister.wasm.gz
	gunzip -fk $<

src/cmc/cycles-minting-canister.wasm.gz:
	curl -Lo $@ https://download.dfinity.systems/ic/$(IC_VERSION)/canisters/cycles-minting-canister.wasm.gz

src/ledger/ledger.private.did:
	curl -Lo $@ https://raw.githubusercontent.com/dfinity/ic/$(IC_VERSION)/rs/rosetta-api/ledger.did

src/ledger/ledger.public.did:
	curl -Lo $@ https://raw.githubusercontent.com/dfinity/ic/$(IC_VERSION)/rs/rosetta-api/ledger_canister/ledger.did

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
		src/ledger/ledger.wasm src/ledger/ledger.private.did src/ledger/ledger.public.did

.PHONY: clean distclean upgrade upgrade_backend upgrade_frontend download deploy
