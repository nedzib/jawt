# AGENTS.md

JAWT ("Just Another Workflow Thing") — Ruby gem, terminal workflow orchestrator. Everything (docs, comments, CLI output, test names) is written in **Spanish**; match that in new code.

## Commands

```sh
bundle install                                   # setup (uses Gemfile -> gemspec)
bundle exec rake test                            # full test suite (Minitest; default task)
bundle exec ruby -Ilib -Itest test/config_test.rb   # single test file
gem build jawt.gemspec && gem install ./jawt-0.1.0.gem  # build + install locally
bundle exec ruby exe/jawt <command>              # run the CLI without installing the gem
```

No linter, formatter, type checker, CI, or pre-commit hooks are configured.

## Architecture

- Entry: `lib/jawt.rb` requires everything; `exe/jawt` -> `Jawt::CLI.start`.
- Two-level model:
  - **Workflows** (per-repo, YAML): `<repo>/.jawt/workflows/*.workflow`
  - **Nodes** (global, user-installed): `~/.config/jawt/nodes/<name>/node.toml` + an executable (`main.sh` by default)
- Built-in node types (`start`, `end`, `condition`, `multiplex`, `run`) live in `Node::Builtins`; `Registry.default` merges builtins + user nodes.
- Daemon state: unix socket `~/.config/jawt/daemon.sock`, pid file, per-run logs in `~/.config/jawt/logs/`, global config `~/.config/jawt/config.toml` (TOML via `toml-rb`, `repos = [...]` list).
- Version string lives only in `lib/jawt/version.rb` (`Jawt::VERSION`); the gemspec reads it.

## Design intent

Al diseñar un workflow, sus nodos deben ser **granulares y de una sola responsabilidad** (responsabilidad reducida). Compón flujos orquestando nodos pequeños y reutilizables en lugar de escribir un nodo "script" que haga varias cosas a la vez. Si una tarea se puede descomponer (ej. listar, filtrar, decidir, actuar), hazlo en nodos separados; el `multiplex` + la convención `action: "skipped"` permiten encadenarlos sin ramificar el grafo.

## Gotchas

- The `run` node executes `$SHELL -lic` by default (login + interactive, sources `.zshrc`). Any test or example using `run` **must** set `shell: /bin/sh`, `interactive: false`, `login: false` for deterministic output. See `test/runner_test.rb`.
- Workflows are parsed with `YAML.safe_load(source, aliases: true)`; node `config` keys are everything except `type`.
- `condition` expressions support only a fixed operator set (`== != > < >= <= =~`) evaluated in `Runner#evaluate`.
- User-node executables are resolved from `[node.exec, main.sh, main.rb, main.py, run]`, then run with `ruby`/`python3`/`sh` by extension.
- Config interpolation uses `${node.field}` (`Runner#resolve`) against prior node outputs.
- Tests isolate filesystem state with `Dir.mktmpdir`; `daemon_test.rb` spawns a real `Daemon` thread + unix socket and uses `wait_for` polling.
- No `LICENSE` file exists even though `jawt.gemspec` lists it in `spec.files` — don't add a new dependency on it.
