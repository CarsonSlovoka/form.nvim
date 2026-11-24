NVIM ?= nvim

.PHONY: test

test:
	$(NVIM) --headless -u NONE -i NONE -n -l tests/schema_test.lua
	$(NVIM) --headless -u NONE -i NONE -n -l tests/form_test.lua
