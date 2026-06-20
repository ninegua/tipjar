DIST_DIR=./dist
IMAGES_SRC=$(wildcard src/tipjar_assets/assets/*.png) $(wildcard src/tipjar_assets/assets/*/*/*.png) $(wildcard src/tipjar_assets/assets/*.ico)
ASSETS_SRC=$(wildcard src/tipjar_assets/src/*.html) $(wildcard src/tipjar_assets/src/*.js) src/tipjar_assets/assets/tipjar.webmanifest src/tipjar_assets/assets/faq.html
TIPJAR_SRC=$(wildcard src/tipjar/*.mo)
LOGGER_SRC=$(wildcard src/logger/*.mo)
IC_VERSION=a17247bd86c7aa4e87742bf74d108614580f216d

build: dist/tipjar.wasm dist/logger.wasm

download: src/blackhole/blackhole.did src/blackhole/blackhole-opt.wasm \
	src/ledger/ledger.did src/cmc/cmc.did src/cycles_ledger/cycles-ledger.did

src/blackhole/blackhole.did.mo: src/blackhole/blackhole.did
	didc bind --target mo $< > $@

src/blackhole/blackhole.did:
	curl -Lo $@ https://github.com/ninegua/ic-blackhole/releases/download/0.0.0/blackhole.did

src/blackhole/blackhole-opt.wasm:
	curl -Lo $@ https://github.com/ninegua/ic-blackhole/releases/download/0.0.0/blackhole-opt.wasm

src/cycles_ledger/cycles-ledger.did:
	curl -Lo $@ https://github.com/dfinity/cycles-ledger/releases/download/cycles-ledger-v1.0.2/cycles-ledger.did
	sed -e 's/vec nat8/blob/' -i $@

src/ledger/ledger.did:
	curl -Lo $@ https://raw.githubusercontent.com/dfinity/ic/$(IC_VERSION)/rs/rosetta-api/icp_ledger/ledger.did

src/cmc/cmc.did:
	curl -Lo $@ https://raw.githubusercontent.com/dfinity/ic/$(IC_VERSION)/rs/nns/cmc/cmc.did

dist/tipjar.wasm dist/tipjar.did &: $(TIPJAR_SRC)
	moc --public-metadata candid:service --public-metadata candid:args --public-metadata motoko:compiler \
		--idl -c -o $@ $$(vessel sources) \
		--actor-id-alias cmc rkp4c-7iaaa-aaaaa-aaaca-cai src/cmc/cmc.did \
		--actor-id-alias cycles_ledger um5iw-rqaaa-aaaaq-qaaba-cai src/cycles_ledger/cycles-ledger.did \
		--actor-id-alias ledger ryjl3-tyaaa-aaaaa-aaaba-cai src/ledger/ledger.did \
		src/tipjar/main.mo

dist/logger.wasm dist/logger.did &: $(LOGGER_SRC)
	moc --public-metadata candid:service --public-metadata candid:args --public-metadata motoko:compiler \
		--idl -c -o $@ $$(vessel sources) \
		src/logger/TextLogger.mo

src/tipjar_assets/assets/faq.html: FAQ.md
	tail -n"$$(($$(wc -l FAQ.md|cut -d\  -f1) - 1))" $< | \
		pandoc --css=https://cdn.simplecss.org/simple.min.css --toc --toc-depth=6 \
		--template=template.html -f markdown -t html --shift-heading-level-by=3 > $@

clean:
	rm src/tipjar_assets/assets/faq.html

distclean: clean
	rm src/blackhole/blackhole.did src/blackhole/blackhole-opt.wasm \
		src/ledger/ledger.did src/cmc/cmc.did

.PHONY: clean distclean download build
