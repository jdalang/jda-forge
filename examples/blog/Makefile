APP   = blog
FORGE = ../../forge.jda
OUT   = _build/$(APP).jda

CONFIG      = config/application.jda
HELPERS     = $(shell find app/helpers     -name "*.jda"      2>/dev/null | sort)
MODELS      = $(shell find app/models      -name "*.jda"      2>/dev/null | sort)
VIEWS       = $(shell find app/views       -name "*.html.jda" 2>/dev/null | sort)
CONTROLLERS = $(shell find app/controllers -name "*.jda"      2>/dev/null | sort)
ROUTES      = _build/routes.jda
CTRL_INIT   = _build/controllers.jda
MODELS_GEN  = _build/models.jda
ASSETS_GEN  = _build/assets.jda
MAIN        = main.jda

SRC = $(CONFIG) $(HELPERS) $(MODELS_GEN) $(ASSETS_GEN) $(MODELS) $(VIEWS) $(CONTROLLERS) $(CTRL_INIT) $(ROUTES) $(MAIN)

TEST_SRC = $(CONFIG) $(HELPERS) $(MODELS_GEN) $(MODELS) $(VIEWS) $(CONTROLLERS) $(CTRL_INIT) $(ROUTES) \
           $(shell find test -name "*.jda" 2>/dev/null | sort)
TEST_OUT = _build/test.jda

.PHONY: all build run watch test clean _gen

all: build

_gen:
	@forge compile-routes
	@forge compile-models
	@forge compile-assets

build: _gen $(OUT)
	jda build --include $(FORGE) $(OUT) -o $(APP)

$(OUT): $(SRC)
	@mkdir -p _build
	@cat $(SRC) > $(OUT)
	@echo "merged $(words $(SRC)) files → $(OUT)"

run: build
	./$(APP)

watch:
	@{ find app config db -name "*.jda" -o -name "*.html.jda" -o -name "*.sql" \
	       -o -name "*.css" -o -name "*.js"; } \
	    | entr -rn sh -c 'forge compile-routes 2>/dev/null; forge compile-models 2>/dev/null; forge compile-assets 2>/dev/null; make run'

test: _gen $(TEST_OUT)
	jda build --include $(FORGE) $(TEST_OUT) -o test_runner
	FORGE_ENV=test ./test_runner

$(TEST_OUT): $(TEST_SRC)
	@mkdir -p _build
	@cat $(TEST_SRC) > $(TEST_OUT)

clean:
	rm -rf _build $(APP) test_runner
