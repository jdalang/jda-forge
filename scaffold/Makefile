# =============================================================================
# JDA Forge — Project Makefile
# =============================================================================
# Build:   make
# Run:     make run
# Watch:   make watch     (requires entr: brew install entr)
# Clean:   make clean
# =============================================================================

APP      = app
FORGE    = ../forge.jda
OUT      = _build/$(APP).jda

# Source files — order matters for readability but Jadn resolves all names
CONFIG   = config.jda
MW       = $(wildcard middleware/*.jda)
ROUTES   = $(wildcard routes/*.jda)
VIEWS    = $(wildcard views/*.jda)
MAIN     = main.jda

SRC      = $(CONFIG) $(MW) $(VIEWS) $(ROUTES) $(MAIN)

.PHONY: all build run watch clean

all: build

build: $(OUT)
	jda build --include $(FORGE) $(OUT) -o $(APP)

$(OUT): $(SRC)
	@mkdir -p _build
	@cat $(SRC) > $(OUT)
	@echo "forge: merged $(words $(SRC)) files → $(OUT)"

run: build
	./$(APP)

# Rebuild + restart whenever any source file changes
watch:
	@echo "Watching for changes…"
	@ls $(SRC) | entr -r make run

clean:
	rm -rf _build $(APP)
