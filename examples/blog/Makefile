APP   = blog
FORGE = ../../forge.jda
OUT   = _build/$(APP).jda

CONFIG      = config.jda
MODELS      = $(shell find models      -name "*.jda"      | sort)
VIEWS       = $(shell find views       -name "*.html.jda" | sort)
CONTROLLERS = $(shell find controllers -name "*_controller.jda" | sort)
ROUTES      = $(shell find routes      -name "*.jda"      | sort)
MAIN        = main.jda

SRC = $(CONFIG) $(MODELS) $(VIEWS) $(CONTROLLERS) $(ROUTES) $(MAIN)

TEST_SRC = $(CONFIG) $(MODELS) $(VIEWS) $(CONTROLLERS) $(ROUTES) $(shell find test -name "*.jda" | sort)
TEST_OUT = _build/test.jda

.PHONY: all build run watch test clean

all: build

build: $(OUT)
	jda build --include $(FORGE) $(OUT) -o $(APP)

$(OUT): $(SRC)
	@mkdir -p _build
	@cat $(SRC) > $(OUT)
	@echo "merged $(words $(SRC)) files → $(OUT)"

run: build
	./$(APP)

watch:
	@ls $(SRC) | entr -r make run

test: $(TEST_OUT)
	jda build --include $(FORGE) $(TEST_OUT) -o test_runner
	FORGE_ENV=test ./test_runner

$(TEST_OUT): $(TEST_SRC)
	@mkdir -p _build
	@cat $(TEST_SRC) > $(TEST_OUT)

clean:
	rm -rf _build $(APP) test_runner
