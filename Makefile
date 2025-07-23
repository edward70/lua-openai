.PHONY: build test local lint

build:
	moonc llm

test: build
	busted

local: build
	luarocks --lua-version=5.1 make --local lua-llm-dev-1.rockspec

lint:
	moonc -l llm

tags::
	moon-tags $$(git ls-files llm/ | grep -i '\.moon$$') > $@
