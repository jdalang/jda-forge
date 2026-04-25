APP   = blog
FORGE = ../../forge.jda
OUT   = _build/$(APP).jda

CONFIG      = config/application.jda
HELPERS     = $(shell find app/helpers     -name "*.jda"      2>/dev/null | sort)
MODELS      = $(shell find app/models      -name "*.jda"      2>/dev/null | sort)
VIEWS       = $(shell find app/views       -name "*.html.jda" 2>/dev/null | sort)
CONTROLLERS = $(shell find app/controllers -name "*.jda"      2>/dev/null | sort)
CONTROLLERS_INIT = config/controllers.jda
ROUTES           = config/routes.jda
MAIN        = main.jda

SRC = $(CONFIG) $(HELPERS) $(MODELS) $(VIEWS) $(CONTROLLERS) $(CONTROLLERS_INIT) $(ROUTES) $(MAIN)

TEST_SRC = $(CONFIG) $(HELPERS) $(MODELS) $(VIEWS) $(CONTROLLERS) $(CONTROLLERS_INIT) $(ROUTES) \
           $(shell find test -name "*.jda" 2>/dev/null | sort)
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
	@find app config -name "*.jda" -o -name "*.html.jda" | entr -r make run

test: $(TEST_OUT)
	jda build --include $(FORGE) $(TEST_OUT) -o test_runner
	FORGE_ENV=test ./test_runner

$(TEST_OUT): $(TEST_SRC)
	@mkdir -p _build
	@cat $(TEST_SRC) > $(TEST_OUT)

clean:
	rm -rf _build $(APP) test_runner
