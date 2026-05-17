# Library Management

JDA Forge uses a `Forgefile` to declare dependencies. Libraries are plain `.jda` files fetched from git repositories and placed in `libs/`.

---

## Forgefile

Every Forge project has a `Forgefile` at the root. `forge new` creates one automatically.

```
# Forgefile

# The framework itself
forge "github.com/jdalang/jda-forge" version "1.0.0"

# Third-party libraries
lib "github.com/jdalang/forge-markdown" version "1.2.0"
lib "github.com/jdalang/forge-slugify" version "1.0.0"
lib "github.com/myorg/jda-payments"                      # no version = latest
```

- `forge` — the framework line (always required)
- `lib` — a third-party library
- `version "x.y.z"` — pin to a specific git tag; omit to use the latest default branch

---

## Installing dependencies

```bash
forge install               # install from Forgefile, generate Forgefile.lock
forge install --locked      # install exact versions from Forgefile.lock (use in CI)
```

`forge install` clones each dependency into `libs/.src/<name>/`, checks out the requested tag, and copies the `.jda` file to `libs/<name>.jda`.

The Makefile auto-discovers all `.jda` files in `libs/`:

```makefile
FORGE = libs/forge.jda
LIBS  = $(filter-out $(FORGE), $(wildcard libs/*.jda))
LINCS = $(addprefix --include ,$(LIBS))

build:
    jda build --include $(FORGE) $(LINCS) $(OUT) -o app
```

---

## Installing a specific version

### In Forgefile

```
lib "github.com/jdalang/forge-markdown" version "1.2.0"
```

### From the command line

```bash
forge add forge-markdown --version v1.2.0
```

This adds the line to `Forgefile` and installs immediately.

### Checking what versions are available

```bash
# See all available tags for an installed library
git -C libs/.src/forge-markdown tag | sort -V

# Or browse GitHub releases
# https://github.com/jdalang/forge-markdown/releases
```

### Switching an installed library to a different version

Edit `Forgefile` to change the version, then:

```bash
forge update forge-markdown
```

Or to roll back to a known-good version:

```bash
forge add forge-markdown --version v1.1.0
```

---

## Forgefile.lock

After `forge install`, a `Forgefile.lock` is written:

```
# Forgefile.lock — commit this file
forge jda-forge       github.com/jdalang/jda-forge         v1.0.0  abc1234
lib   forge-markdown  github.com/jdalang/forge-markdown     v1.2.0  def5678
lib   forge-slugify   github.com/jdalang/forge-slugify      v1.0.0  9a8b7c6
lib   jda-payments    github.com/myorg/jda-payments         latest  1f2e3d4
```

**Commit `Forgefile.lock`** so every developer and CI run installs the exact same code.

```bash
# Developer machine
forge install               # installs and updates lock

# CI / production deploy
forge install --locked      # never changes lock, errors if missing
```

---

## Updating libraries

```bash
forge update                    # update all libs to latest/pinned version
forge update forge-markdown     # update one library only
```

After updating, review `Forgefile.lock` changes in git before committing.

---

## Using a private or local library

```bash
# Private GitHub repo (SSH)
forge add mylib git@github.com:myorg/private-lib.git

# Any HTTPS git URL
forge add mylib https://gitlab.com/myorg/jda-mylib.git

# Local path (useful during development of a library)
# Copy the .jda file directly — no forge add needed
cp ~/projects/my-lib/my-lib.jda libs/my-lib.jda
```

For local files, add a comment in `Forgefile`:

```
# lib "local: ~/projects/my-lib/my-lib.jda"  (manually copied, not managed by forge)
```

---

## Writing a library

A library is a single `.jda` file at the root of a git repository. Name it after the repo.

```
my-lib/
  my-lib.jda       ← the library (one file)
  README.md
  CHANGELOG.md
```

Tag releases with semantic versioning:

```bash
git tag v1.0.0
git push origin v1.0.0
```

Users can then pin it with `version "1.0.0"` in their `Forgefile`.

### Naming convention

- Official libraries: `github.com/jdalang/forge-<name>`
- Community libraries: any git URL

---

## Listing installed libraries

```bash
forge list
```

Output:

```
Installed libraries (libs/*.jda):

  forge                        4488 lines   libs/forge.jda
  forge-markdown                312 lines   libs/forge-markdown.jda
  forge-slugify                  48 lines   libs/forge-slugify.jda

Forgefile.lock:
  forge   jda-forge      v1.0.0   abc1234
  lib     forge-markdown v1.2.0   def5678
  lib     forge-slugify  v1.0.0   9a8b7c6
```
