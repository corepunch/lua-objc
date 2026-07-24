CC = clang
CFLAGS = -fobjc-arc -Wall -O2 $(shell pkg-config --cflags lua 2>/dev/null || echo "-I/opt/homebrew/include/lua")
LDFLAGS = $(shell pkg-config --libs lua 2>/dev/null || echo "-L/opt/homebrew/lib -llua -lm") -framework Cocoa

TARGET = lua-objc
SRC = src/main.m

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

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

clean:
	rm -f $(TARGET)

.PHONY: all run clean run-hello run-list run-live run-weather run-welcome
