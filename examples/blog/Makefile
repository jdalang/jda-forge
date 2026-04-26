APP   = blog
OUT   = _build/$(APP).jda

FORGE = libs/forge.jda
LIBS  = $(filter-out $(FORGE), $(wildcard libs/*.jda))

CONFIG      = config/application.jda
HELPERS     = $(shell find app/helpers  -name "*.jda" 2>/dev/null | sort)
MODELS      = $(shell find app/models   -name "*.jda" 2>/dev/null | sort)
MAILERS     = $(shell find app/mailers  -name "*.jda" 2>/dev/null | sort)
ROUTES      = _build/routes.jda
CTRL_INIT   = _build/controllers.jda
MODELS_GEN  = _build/models.jda
VIEWS_GEN   = _build/views.jda
ASSETS_GEN  = _build/assets.jda
MAIN        = main.jda

SRC = $(CONFIG) $(HELPERS) $(MODELS_GEN) $(VIEWS_GEN) $(ASSETS_GEN) $(MODELS) $(MAILERS) $(CTRL_INIT) $(ROUTES) $(MAIN)

TEST_SRC = $(CONFIG) $(HELPERS) $(MODELS_GEN) $(VIEWS_GEN) $(ASSETS_GEN) $(MODELS) $(MAILERS) $(CTRL_INIT) $(ROUTES) \
           $(shell find test -name "*.jda" 2>/dev/null | sort)
TEST_OUT = _build/test.jda

.PHONY: all build run watch test clean _gen

all: build

_gen:
	@forge compile-routes
	@forge compile-models
	@forge compile-views
	@forge compile-assets

build: _gen $(OUT)
	jda $(OUT) -o $(APP)

$(OUT): $(FORGE) $(LIBS) $(SRC)
	@mkdir -p _build
	@cat $(FORGE) $(LIBS) $(SRC) > $(OUT)
	@echo "merged $(words $(FORGE) $(LIBS) $(SRC)) files → $(OUT)"

run: build
	./$(APP)

watch:
	@{ find app config db libs -name "*.jda" -o -name "*.html.jda" -o -name "*.sql" \
	       -o -name "*.css" -o -name "*.js"; } \
	    | entr -rn sh -c 'forge compile-routes 2>/dev/null; forge compile-models 2>/dev/null; forge compile-views 2>/dev/null; forge compile-assets 2>/dev/null; make run'

test: _gen $(TEST_OUT)
	jda $(TEST_OUT) -o test_runner
	FORGE_ENV=test ./test_runner

$(TEST_OUT): $(FORGE) $(LIBS) $(TEST_SRC)
	@mkdir -p _build
	@cat $(FORGE) $(LIBS) $(TEST_SRC) > $(TEST_OUT)

clean:
	rm -rf _build $(APP) test_runner
