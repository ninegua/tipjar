DIST_DIR=./dist
TIPJAR_SRC=$(wildcard src/tipjar/*.mo)
LOGGER_SRC=$(wildcard src/logger/*.mo)
FRONTEND_SRC=$(wildcard src/frontend/*) $(wildcard src/public/*) src/public/faq.html
TIPJAR_DEPS=dist/blackhole.did dist/icp-ledger.did dist/cmc.did dist/cycles-ledger.did
FRONTEND_DEPS=dist/tipjar.js dist/cycles-ledger.js dist/icp-ledger.js
IC_VERSION=a17247bd86c7aa4e87742bf74d108614580f216d

build: backend frontend

backend: download dist/tipjar.wasm dist/logger.wasm

frontend: dist/frontend/index.js

download: $(TIPJAR_DEPS) dist/blackhole-opt.wasm

dist/blackhole.did.mo: dist/blackhole.did
	didc bind --target mo $< > $@

dist/blackhole.did: | dist
	curl -Lo $@ https://github.com/ninegua/ic-blackhole/releases/download/0.0.0/blackhole.did

dist/blackhole-opt.wasm: | dist
	curl -Lo $@ https://github.com/ninegua/ic-blackhole/releases/download/0.0.0/blackhole-opt.wasm

dist/cycles-ledger.did: | dist
	curl -Lo $@ https://github.com/dfinity/cycles-ledger/releases/download/cycles-ledger-v1.0.2/cycles-ledger.did
	sed -e 's/vec nat8/blob/' -i $@

dist/icp-ledger.did: | dist
	curl -Lo $@ https://raw.githubusercontent.com/dfinity/ic/$(IC_VERSION)/rs/rosetta-api/icp_ledger/ledger.did

dist/cmc.did: | dist
	curl -Lo $@ https://raw.githubusercontent.com/dfinity/ic/$(IC_VERSION)/rs/nns/cmc/cmc.did

dist/%.js: dist/%.did | dist
	didc bind -t js $< > $@

dist:
	mkdir -p $@

dist/tipjar.wasm dist/tipjar.did &: $(TIPJAR_SRC) $(TIPJAR_DEPS) | dist
	moc --public-metadata candid:service --public-metadata candid:args --public-metadata motoko:compiler \
		--idl -c -o $@ $$(vessel sources) \
		--actor-id-alias cmc rkp4c-7iaaa-aaaaa-aaaca-cai dist/cmc.did \
		--actor-id-alias cycles_ledger um5iw-rqaaa-aaaaq-qaaba-cai dist/cycles-ledger.did \
		--actor-id-alias icp_ledger ryjl3-tyaaa-aaaaa-aaaba-cai dist/icp-ledger.did \
		src/tipjar/main.mo

dist/logger.wasm dist/logger.did &: $(LOGGER_SRC) | dist
	moc --public-metadata candid:service --public-metadata candid:args --public-metadata motoko:compiler \
		--idl -c -o $@ $$(vessel sources) \
		src/logger/TextLogger.mo

dist/frontend/index.js: $(FRONTEND_DEPS) $(FRONTEND_SRC)
	npm run build

src/public/faq.html: FAQ.md
	tail -n"$$(($$(wc -l FAQ.md|cut -d\  -f1) - 1))" $< | \
		pandoc --css=https://cdn.simplecss.org/simple.min.css --toc --toc-depth=6 \
		--template=template.html -f markdown -t html --shift-heading-level-by=3 > $@

clean:
	rm -f src/public/faq.html

distclean: clean
	rm -rf dist

.PHONY: clean distclean download build frontend backend
