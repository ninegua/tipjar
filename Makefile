DIST_DIR=./dist
TIPJAR_SRC=$(wildcard src/tipjar/*.mo)
LOGGER_SRC=$(wildcard src/logger/*.mo)
FRONTEND_SRC=$(wildcard src/frontend/*) $(wildcard src/public/*) src/public/faq.html
FRONTEND_DEPS=dist/tipjar.js dist/cycles-ledger.js dist/icp-ledger.js
IC_VERSION=a17247bd86c7aa4e87742bf74d108614580f216d
MOC_FLAGS?=$(shell vessel sources) --enhanced-orthogonal-persistence
TESTS=Util
TEST_TARGETS=$(TESTS:%=run/%)
DIDC?=didc

BLACKHOLE_WASM?=dist/blackhole-opt.wasm
BLACKHOLE_DID?=dist/blackhole.did
CMC_DID?=dist/cmc.did
ICP_LEDGER_DID?=dist/icp-ledger.did
CYCLES_LEDGER_DID?=dist/cycles-ledger.did
TIPJAR_DEPS=$(BLACKHOLE_DID) $(CMC_DID) $(ICP_LEDGER_DID) $(CYCLES_LEDGER_DID)

build: backend frontend $(BLACKHOLE_WASM)

backend: dist/tipjar.wasm dist/logger.wasm

frontend: dist/frontend/index.js

download: $(TIPJAR_DEPS)

dist/blackhole.did.mo: $(BLACKHOLE_DID)
	$(DIDC) bind --target mo $< > $@

$(BLACKHOLE_DID): | dist
	curl -Lo $@ https://github.com/ninegua/ic-blackhole/releases/download/0.0.0/blackhole.did

$(BLACKHOLE_WASM): | dist
	curl -Lo $@ https://github.com/ninegua/ic-blackhole/releases/download/0.0.0/blackhole-opt.wasm

$(CYCLES_LEDGER_DID): | dist
	curl -Lo $@ https://github.com/dfinity/cycles-ledger/releases/download/cycles-ledger-v1.0.2/cycles-ledger.did

dist/cycles-ledger-fixed.did: $(CYCLES_LEDGER_DID)
	sed -e 's/vec nat8/blob/' $< > $@

$(ICP_LEDGER_DID): | dist
	curl -Lo $@ https://raw.githubusercontent.com/dfinity/ic/$(IC_VERSION)/rs/rosetta-api/icp_ledger/ledger.did

$(CMC_DID): | dist
	curl -Lo $@ https://raw.githubusercontent.com/dfinity/ic/$(IC_VERSION)/rs/nns/cmc/cmc.did

dist/%.js: dist/%.did | dist
	didc bind -t js $< > $@

node_modules:
	npm i

dist:
	mkdir -p $@

dist/tipjar.wasm dist/tipjar.did &: $(TIPJAR_SRC) $(TIPJAR_DEPS) dist/cycles-ledger-fixed.did dist/blackhole.did.mo | dist
	moc --public-metadata candid:service --public-metadata candid:args --public-metadata motoko:compiler \
		--idl -c -o $@ $(MOC_FLAGS) \
		--actor-id-alias cmc rkp4c-7iaaa-aaaaa-aaaca-cai $(CMC_DID) \
		--actor-id-alias cycles_ledger um5iw-rqaaa-aaaaq-qaaba-cai dist/cycles-ledger-fixed.did \
		--actor-id-alias icp_ledger ryjl3-tyaaa-aaaaa-aaaba-cai $(ICP_LEDGER_DID) \
		src/tipjar/main.mo

dist/logger.wasm dist/logger.did &: $(LOGGER_SRC) | dist
	moc --public-metadata candid:service --public-metadata candid:args --public-metadata motoko:compiler \
		--idl -c -o $@ $(MOC_FLAGS) \
		src/logger/TextLogger.mo

dist/frontend/index.js: $(FRONTEND_DEPS) $(FRONTEND_SRC) | dist node_modules
	npm run build

src/public/faq.html: FAQ.md
	tail -n"$$(($$(wc -l FAQ.md|cut -d\  -f1) - 1))" $< | \
		pandoc --css=https://cdn.simplecss.org/simple.min.css --toc --toc-depth=6 \
		--template=template.html -f markdown -t html --shift-heading-level-by=3 > $@

test: $(TEST_TARGETS)

run/%: src/tests/%.mo $(TIPJAR_SRC)
	moc $(MOC_FLAGS) -r $<

clean:
	rm -f src/public/faq.html

distclean: clean
	rm -rf dist

.PHONY: clean distclean download build frontend backend
