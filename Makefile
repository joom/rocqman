CRANE_DIR := crane
BUILD_DIR := _build/RocqmanGame
SRC_DIR   := src
GEN_DIR   := $(SRC_DIR)/generated
UNAME_S := $(shell uname -s)

ifeq ($(origin CXX), default)
  CXX := c++
endif
LDFLAGS :=

ifeq ($(UNAME_S),Darwin)
  BREW_LLVM := $(shell brew --prefix llvm 2>/dev/null)
  BREW_CLANG := $(BREW_LLVM)/bin/clang++
  ifneq ($(wildcard $(BREW_CLANG)),)
    CXX := $(BREW_CLANG)
    LDFLAGS := -L$(BREW_LLVM)/lib/c++ -Wl,-rpath,$(BREW_LLVM)/lib/c++
  endif
endif

IS_CLANG := $(shell $(CXX) --version 2>/dev/null | grep -qi clang && echo yes)
BRACKET_DEPTH_FLAG :=
ifeq ($(IS_CLANG),yes)
  BRACKET_DEPTH_FLAG := -fbracket-depth=1024
endif

SDL2_CFLAGS := $(shell pkg-config --cflags sdl2 SDL2_image)
SDL2_LIBS   := $(shell pkg-config --libs sdl2 SDL2_image)

CXXFLAGS := -std=c++23 $(BRACKET_DEPTH_FLAG) -I$(GEN_DIR) -I$(SRC_DIR) -I$(CRANE_DIR)/theories/cpp $(SDL2_CFLAGS)
OPT ?= -O0

.PHONY: all clean run extract check-crane

all: rocqman

check-crane:
	@test -d $(CRANE_DIR)/theories/cpp || \
	  (echo "error: Crane submodule not found at ./$(CRANE_DIR)"; \
	   echo "run: git submodule update --init --recursive"; \
	   exit 1)

# Extract Rocq -> C++ and copy to a stable directory
extract: check-crane theories/Rocqman.v theories/SDL.v
	dune clean
	dune build theories/Rocqman.vo
	@mkdir -p $(GEN_DIR)
	cp $(BUILD_DIR)/rocqman.h $(BUILD_DIR)/rocqman.cpp $(GEN_DIR)/

# Only re-extract if generated files are missing or source changed
$(GEN_DIR)/rocqman.cpp $(GEN_DIR)/rocqman.h: theories/Rocqman.v theories/SDL.v
	$(MAKE) extract

rocqman: check-crane $(GEN_DIR)/rocqman.cpp $(GEN_DIR)/rocqman.h
	$(CXX) $(CXXFLAGS) $(OPT) $(LDFLAGS) $(SDL2_LIBS) $(GEN_DIR)/rocqman.cpp -o rocqman

clean:
	dune clean
	rm -rf rocqman $(GEN_DIR) rocqman.dSYM

run: rocqman
	./rocqman
