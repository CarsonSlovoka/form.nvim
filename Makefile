NVIM ?= nvim

.PHONY: test

test:
	$(NVIM) --headless -u NONE -i NONE -n -l tests/schema_test.lua
	$(NVIM) --headless -u NONE -i NONE -n -l tests/serialize_test.lua
	$(NVIM) --headless -u NONE -i NONE -n -l tests/writer_test.lua
	$(NVIM) --headless -u NONE -i NONE -n -l tests/form_test.lua
	$(NVIM) --headless -u NONE -i NONE -n -l tests/output_test.lua
