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

clean:
	rm -f $(TARGET)

.PHONY: all run clean
