# Topcoat Releases — Timeline and Upgrade Checklists

Source: [GitHub releases](https://github.com/tokio-rs/topcoat/releases) (v0.5.0–v0.10.0) and the Tokio blog posts [Announcing Topcoat](https://tokio.rs/blog/2026-07-22-announcing-topcoat) (2026-07-22) and [Topcoat is pushing the boundary of server applications](https://tokio.rs/blog/2026-09-24-topcoat-server-applications) (2026-09-24).

Always upgrade the CLI with the crate: `cargo install topcoat-cli --version <X.Y.Z> --locked`. Upgrade one minor version at a time; each checklist is mechanical.

## Timeline

| Version | Date | Headline |
|---|---|---|
| 0.5.0 | 2026-07-27 | WebSockets, SSE, Datastar, `topcoat-mail`, wasm/listener-less (`serve` feature), Unix sockets, `TowerRoute`, multi-method routes, signal shorthands |
| 0.6.0 | 2026-08-17 | Concurrent component rendering, `href!`, immutable scoped `Cx::with`, 17 UI components, request rewrites, global `OriginPolicy`, 2 MiB body limit, `not_found!`, `path_param!`, sitemaps, memoize by 128-bit hash |
| 0.6.1 | 2026-08-18 | Rewrite through `discover` routing; await in runtime `if`/blocks |
| 0.6.2 | 2026-08-18 | Mount a Topcoat router as an axum service |
| 0.7.0 | 2026-09-05 | **Streaming SSR** (`live!`/`emit!`, `suspense`, `error_boundary`); **views are lazy**, `Result<impl View>` signatures |
| 0.8.0 | 2026-09-09 | **Signals as functions** `signal(cx, ..)`, tracked server reads, page reruns, morphing, `Signal<T>` shard params, `.runtime()` required |
| 0.8.1 | 2026-09-13 | `./` relative module paths, trailing-slash policy, `see_other` as page error, cookies on error responses, `response_headers(cx)` |
| 0.9.0 | 2026-09-24 | **Server push** (`connected(cx)` + WebSocket), `SuspenseMode::Wait`, `#[key]` loops, richer expressions (all ints, vecs), stateful hot reload, explicit shard/procedure paths, `client_ip` + `TrustedProxies`, cloneable `Error` |
| 0.10.0 | 2026-10-03 | **Client-side navigation** (`runtime::link`, `link_attrs`, prefetch), `#[record]` structs, tuples in expressions, one shared WebSocket per document (shards rerender independently), **`module_param!`** split from `path_param!`, `topcoat ui add --all`, `topcoat fmt --rustfmt`/`--check`, `topcoat --version`, `default-run`, `docs/` + `llms.txt` |

Direction (blog, roadmap): server-side rendering by default with drop-down to zero-latency client UI; conventions that help LLM-driven development (0.10 ships [`llms.txt`](https://github.com/tokio-rs/topcoat/blob/main/llms.txt)); Toasty as the DB layer. Roadmap items not yet shipped: `topcoat new`, static export, validations, i18n, OpenAPI, deploy docs, background jobs, auth, islands.

## 0.4 → 0.5

- Router errors moved: `use topcoat::router::error::{NotFoundError, RouterErrorExt, SeeOther, not_found, see_other}`.
- Bodies moved: `use topcoat::router::content::{Css, Form, Html, Json, RawForm, multipart::Multipart}`.
- Tower moved: `topcoat::router::tower::{TowerLayer, TowerRoute}`.
- `AssetConfig::hosted_at(base_url, bundle)` (URL first); `asset!` returns a handle, use `.id()` for bundle lookups.
- `session::Config` → `SessionConfig`.
- `default-features = false` builds must add `serve` to keep `topcoat::serve/start`.
- Boolean attrs render `disabled=""` (update snapshots).

## 0.5 → 0.6

- **Update the CLI first**: bundle path moved to `target/<profile>/assets`.
- `CxBuilder` removed; `Cx::insert`/`get_mut` → `cx.with(v)` / `cx.with_many((a, b))`; layers take `&Cx` and pass the child to `next.run(&cx, body)`; `Cx::detach` → `cx.clone()`; `ContextMap` → `AppContext`.
- Origin verification on for every router: cross-origin POST/PUT/PATCH/DELETE and WS handshakes → 403. Migrate `SessionConfigBuilder::trust_origin` → `.origin_policy(OriginPolicy::new().trust_origins([..]))`.
- Bodies capped at 2 MiB: add `.layer(BodyLimit::max(n).at("/upload"))` for uploads. `TowerLayer::new(l).at("/api")` (no path arg).
- Unmatched URLs skip layers/layouts: add `not_found!("/")` for branded 404s.
- `#[path_param] struct PostId(u64)` → `path_param!(post_id: u64, error = bad_request)` (then `module_param!` in 0.10 when it names a module segment).
- `request`/`response` modules: `topcoat::router::request::{headers, uri, ..}`, `topcoat::router::response::{IntoResponse, Response}`.
- `#[memoize]` on `Option`/`Result` returns `&Option<T>`; add `#[memoize(as_ref)]` for the old `Option<&T>`.
- `View::render(self)` consumes; `class!` literal type is `StaticClass`; `topcoat ui update` for vendored components.
- Build panics on layers that match no route. Cookie writes after the response started panic.

## 0.6 → 0.7 (largest migration)

- Return types: `-> Result` → `-> Result<impl View>`, body `Ok(view! { .. })`, drop `?` after `view!`. Import `View` from `topcoat::view`.
- Layouts: `slot: Result` → `slot: Slot<'_>` (from `topcoat::router`); `(slot?)` → `(slot)`.
- Child content: `child: View` → `#[default] child: Child<'_>`.
- Recursion: `#[component(boxed)]` → `.boxed()` on the view (`topcoat::view::ViewExt`).
- Layout error matching → `error_boundary(fallback: |error| .., (slot))` with downcast + rethrow.
- Redirect-only pages return `Result<()>`.
- Views in tuples (htmx/Datastar headers) resolve with `.single().await?` → `ViewHandle`.
- Views move-capture like `async move`: clone values used after building a view.
- Cookie writes must happen before streaming.

## 0.7 → 0.8

- `signal name = value;` inside `view!` → `let name = signal(cx, || value);` before the view; add `cx: &Cx` to the function.
- Add `.runtime()` to the router wherever `topcoat::runtime::script()` renders.
- Shards whose only job was shipping a signal to the server → tracked read (`name.get()` in plain Rust) in the page; state that lived outside a shard for persistence moves back inside as a signal.
- Give reorderable list items an `id` (morphing).
- Signal values read on the server are user input: validate.

## 0.8.0 → 0.8.1

- `/users/` vs `/users` now 308-redirects (was 404). `.trailing_slash(TrailingSlash::Strict)` for the old behavior.
- `Path` segments can end with an empty static segment: check `has_trailing_slash`.
- Page-level form redirects: `return Err(see_other(uri).into());`.
- Absolute paths below a module → `./` relative paths to stay module-routed.
- Headers that must also land on errors → `response_headers(cx).append(..)` in the layer.

## 0.8.1 → 0.9

```toml
topcoat = "0.9"
```

```sh
cargo install topcoat-cli --version 0.9.0 --locked
```

- Router: import `topcoat::runtime::RouterBuilderRuntimeExt`, call `.runtime()` once, **after** application layers; keep `.assets(..)` and `runtime::script()` in `<head>`.
- `.procedure(name)` / `.shard(name)` → `.route(name)` or `.discover()`; drop old registration trait imports.
- Component `key:` props → `#[key(item.id)]` on the `for` loop; per-item helper calls get `&cx.keyed(item.id)`.
- `Error` no longer wraps anyhow: enable `anyhow` feature + `Error::from_anyhow(e)`; owned/mutable downcasts need unique ownership, use `downcast_cloned` for shared errors.
- Rewrites: `.cx(cx.with(value))` → `.with(value)`.
- Vendored UI: `topcoat ui update`, merge new theme tokens (card, popover, sidebar colors).
- Server push: emit current content, `if !connected(cx) { break Ok(token); }`, then await changes.
- Optional: stable endpoints `#[shard("/x")]` / `#[procedure("/api/x")]`; `SuspenseMode::Wait`; `TrustedProxies` + `client_ip(cx)`; `.public_dir(..)`/`.serve_dir(..)` (`fs` feature); `StripPrefixLayer` for mounted services.

## 0.9 → 0.10

```toml
topcoat = "0.10"
```

```sh
cargo install topcoat-cli --version 0.10.0 --locked
topcoat --version   # new in 0.10
```

**Breaking:**
- **Module parameters.** `path_param!` no longer changes the module's URL segment. In every module that relied on it (e.g. `src/app/posts/post_id.rs` → `/posts/{post_id}`), replace it with `module_param!` and import `topcoat::router::module_param`. Catch-all modules: `path_param!(*rest)` → `module_param!(*rest)`. Options and the generated type (`PostId`) are unchanged, so `path_param::<PostId>(cx)` and `href!(post, PostId(id))` stay. Missing this compiles but serves a static segment and **panics** when the param is read.
  - Keep `path_param!` when the handler path declares the capture (`#[page("/posts/{post_id}")]`, `#[page("./{comment_id}")]`); several `path_param!`s per module are now allowed.
  - A module has one `module_param!` **or** one `segment!`, never both.
- **String lengths.** `String::len()`/`str::len()` in runtime expressions return `usize` (was `f64`): `expr!(name.get().len() > 100.0)` → `expr!(name.get().len() > 100usize)`. Still UTF-8 bytes.
- **Runtime script tag.** Render `topcoat::runtime::script()`; replace hand-written `<script src=(runtime::SCRIPT)>` tags. The helper emits `data-topcoat-usize-bits`, which the browser needs for `usize` lengths.
- **WebSocket render cap.** 64 simultaneous renders per connection; extras get `429`. Raise with `.max_runs_per_connection(n)` on the router builder if push-heavy pages hit it.
- **Generated endpoint URLs** for shards/procedures are now deterministic (function name + source location) but still move when code moves; keep explicit paths for anything external clients call.

**Adopt:**
- Internal nav: `<a href=(href!(x))>` → `runtime::link(href: href!(x), "Label")`, or spread `link_attrs(cx, href!(x), prefetch_mode(cx))` onto custom anchors. Signals shared by both pages keep values; back/forward restore scroll.
- Prefetch (default `PrefetchMode::Intent`): `.prefetch(PrefetchMode::Viewport)` app-wide, `cx.with(PrefetchMode::Never)` per scope, `prefetch:` per link. **Pages render speculatively: move any mutation out of page bodies** into routes/procedures.
- `#[record]` structs (named fields, no generics, `#[derive(Clone)]` for `.get()`) instead of parallel signals or tuple-encoded state; usable in signals, expressions, procedure args/results. All fields reach the browser, private ones included.
- Tuples in `expr!`/`$(...)`: `(a, b)`, `()`, `(v,)`, `.0` access; no tuple comparison.
- Nested connected shards now rerender on their own over the shared socket: you no longer need to hoist state to avoid rerendering a connected ancestor.
- Tooling: `rustfmt.toml` with `edition = "2024"`, then `topcoat fmt --rustfmt` locally and `topcoat fmt --check --rustfmt` in CI; rust-analyzer `[rustfmt] overrideCommand = ["topcoat", "fmt", "--stdin", "--rustfmt"]`.
- `[package] default-run = "my-app"` when the crate has extra binaries (migrations); `topcoat dev` honors it.
- `topcoat ui add --all [--registry r] [--overwrite]` to vendor every component (`--overwrite` discards local edits).
- Fixed: `cargo topcoat dev|fmt` works again; CLI builds keep `RUSTFLAGS`/wrappers/toolchain; `topcoat::Error` works in `thiserror` `#[from]`/`#[error(transparent)]` variants again.

## Toasty notes (DB layer, separate versioning)

Topcoat does not depend on Toasty; pin it independently (latest 0.11.0, 2026-09-25; the Topcoat repo examples still pin 0.7). Blog-highlighted features and their minimum versions:
- `toasty::update!(user { name: "Alicia", login_count.increment() })` — single `UPDATE` without loading.
- `#[document]` embedded struct stored as JSONB/JSON with typed path filters — 0.9+.
- Polymorphic relations via `#[derive(Embed)] enum` + `#[shared(id)]` + `#[belongs_to(key = id)]` + `#[index(id)]` — 0.9+ (`#[shared]`).
- `#[version]` optimistic concurrency on SQL — 0.8+. Upserts `upsert_by_*` — 0.9+.
