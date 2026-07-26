CC = clang
CFLAGS = -fobjc-arc -Wall -O2 $(shell pkg-config --cflags lua 2>/dev/null || echo "-I/opt/homebrew/include/lua")
LDFLAGS = $(shell pkg-config --libs lua 2>/dev/null || echo "-L/opt/homebrew/lib -llua -lm") -framework Cocoa

TARGET = lua-objc
SRC = src/main.m
NATIVE_PLUGIN = build/ide-controls.dylib
NATIVE_PLUGIN_SRC = src/ide_controls_plugin.m

all: $(TARGET) $(NATIVE_PLUGIN)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

$(NATIVE_PLUGIN): $(NATIVE_PLUGIN_SRC)
	mkdir -p build
	$(CC) $(CFLAGS) -dynamiclib -o $@ $^ $(LDFLAGS)

run: $(TARGET)
	./$(TARGET) $(ARGS)

run-hello: $(TARGET)
	./$(TARGET) examples/hello.lua

run-list: $(TARGET)
	./$(TARGET) examples/list.lua

run-live: $(TARGET)
	./$(TARGET) examples/live.lua

run-weather: $(TARGET)
	./$(TARGET) examples/weather.lua

run-welcome: $(TARGET)
	./$(TARGET) examples/welcome.lua

run-mail: $(TARGET)
	./$(TARGET) examples/mail.lua

run-layout: $(TARGET)
	./$(TARGET) examples/layout.lua

run-ide: $(TARGET)
	./$(TARGET) examples/ide.lua

TEST_FILES = $(wildcard tests/*.test.lua)

test: $(TARGET) $(NATIVE_PLUGIN)
	@passed=0; failed=0; \
	for t in $(TEST_FILES); do \
		echo "--- $$t ---"; \
		if ./$(TARGET) $$t 2>&1; then \
			passed=$$((passed + 1)); \
		else \
			failed=$$((failed + 1)); \
		fi; \
		echo ""; \
	done; \
	echo "$$((passed + failed)) test files: $$passed passed, $$failed failed"; \
	test $$failed -eq 0

clean:
	rm -f $(TARGET) $(NATIVE_PLUGIN)

.PHONY: all run clean test run-hello run-list run-live run-weather run-welcome run-mail run-layout
