#
# Makefile for the simple-race example.
#

CXX = clang
CXXFLAGS = -O3 -ftapir
DFLAGS = -O0 -ftapir -g -fsanitize=cilk

TARGET = simple-race
SRC = simple-race.c

.PHONY: all
all: $(TARGET)

$(TARGET): $(SRC)
	$(CXX) -o $@ $(CXXFLAGS) $^

.PHONY: cilksan
cilksan: $(SRC)
	$(CXX) -o cilksan $(DFLAGS) $^
	./cilksan

.PHONY: clean
clean:
	rm -f $(TARGET) cilkscreen
