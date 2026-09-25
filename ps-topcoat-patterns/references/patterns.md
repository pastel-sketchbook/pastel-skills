# Topcoat Full-Stack Patterns — Reference

Battle-tested patterns for Pastel Sketchbook Topcoat apps — copy, adapt, do **not** reinvent.
Targets **Topcoat 0.9.0** (`tokio-rs/topcoat`), Rust **1.98+**, edition 2024. Full-item snippets come from a scratch app built, tested, and curl-checked against `topcoat = "0.9"` + `toasty = "0.11"` (Rust 1.98.1); short `Ok(view! { .. })` fragments go inside a handler body.

Topcoat is early-stage: expect breaking changes between minor versions. For older apps see [releases.md](releases.md) first.

## 1. Project setup

```sh
cargo new my-app && cd my-app
cargo add topcoat@0.9
cargo add tokio --features rt-multi-thread,macros,sync,time
cargo add serde --features derive
cargo add toasty --features sqlite          # or postgresql / mysql
cargo add tracing tracing-subscriber --features tracing-subscriber/env-filter
cargo add uuid --features v7
cargo add --dev http
cargo install topcoat-cli --version 0.9.0 --locked   # CLI must match the crate
touch Topcoat.toml                                   # marker for editor `topcoat fmt`
```

Check versions with `cargo tree -i topcoat` and `cargo install --list | grep topcoat-cli` (the CLI has no `--version` flag; `topcoat dev` warns on mismatch).

CLI commands:

| Command | Purpose |
|---|---|
| `topcoat dev` | Build, run, rebuild on change, stateful hot reload. `HOST`/`PORT` override bind. Press `r` to rebuild. |
| `topcoat fmt [paths]` | Format `view!`/`live!`/`mail!` bodies. Run with `cargo fmt`. `--stdin` for editors. |
| `topcoat asset bundle [--release]` | Scan the binary for `asset!` and write `target/<profile>/assets`. |
| `topcoat ui init / add <name> / update` | Vendor Topcoat UI components (Tailwind, shadcn-style). |

## 2. Project structure

Keep the app a **binary crate** like the official examples; discovery is link-time. `main.rs` is thin wiring; `app.rs` is the `module_router!()` root.

```
my-app/
  Cargo.toml
  Topcoat.toml            # fmt marker
  build.rs                # only with the tailwind feature
  styles.css              # `topcoat ui init` theme (Tailwind input)
  components.toml         # `topcoat ui` registry state
  src/
    main.rs               # telemetry, DB connect, topcoat::start(app::router(db))
    app.rs                # router(), routes(), root layout, "/" page, tests
    app/
      health.rs           # GET /health
      posts.rs            # GET /posts, POST /posts
      posts/post_id.rs    # GET /posts/{post_id}  (path_param! in this module)
      _marketing.rs       # group: layout, no URL segment
      _marketing/pricing.rs  # GET /pricing
    components.rs         # own + vendored components
    context.rs            # db(cx), current_user(cx), require_auth(cx)
    models.rs             # Toasty models
    telemetry.rs          # tracing init + request-id layer
```

Module names become kebab-case segments (`blog_posts` → `/blog-posts`). `_name` modules are groups. `path_param!` inside a module turns its segment into `{param}`. The macro does not scan files: every module needs a `mod` declaration.

`main.rs`:

```rust
mod app;
mod context;
mod models;
mod telemetry;

use toasty::Db;

#[tokio::main]
async fn main() -> std::io::Result<()> {
    telemetry::init();

    let url = std::env::var("DATABASE_URL").unwrap_or_else(|_| "sqlite::memory:".to_owned());
    let db = Db::builder()
        .models(toasty::models!(crate::*))
        .connect(&url)
        .await
        .map_err(std::io::Error::other)?;
    db.push_schema().await.map_err(std::io::Error::other)?;

    // HOST/PORT from env (default 127.0.0.1:3000); Ctrl+C / SIGTERM drain gracefully.
    topcoat::start(app::router(db)).await
}
```

## 3. Router wiring

Split construction so tests can reuse everything except the environment-dependent asset bundle:

```rust
use toasty::Db;
use topcoat::{
    asset::{AssetBundle, RouterBuilderAssetExt},
    cookie::RouterBuilderCookieExt,
    router::{Router, RouterBuilder, RouterBuilderDiscoverExt, module_router},
    runtime::RouterBuilderRuntimeExt,
};

/// Order matters: handlers + layers, values, then `.runtime()` last.
pub fn router(db: Db) -> Router {
    routes(db)
        .assets(AssetBundle::load().expect("asset bundle missing: run `topcoat asset bundle`"))
        .runtime()
        .build()
}

/// Handlers and app values without the asset bundle; tests build on this.
pub fn routes(db: Db) -> RouterBuilder {
    module_router!()          // module-derived pages/layouts/layers/routes
        .discover()           // explicit-path handlers, shards, procedures, #[layer("/")]
        .app_context(db)      // one value per type
        .app_context(Chat::default())
        .cookies()            // required by cookies(cx) and sessions
}
```

**Rules:**
- `module_router!()` must be called in the root route module and registers only module-derived handlers. Chain `.discover()` for the rest.
- Register application layers **before** `.runtime()`; `RuntimeLayer` turns page-rerun `POST`s into `GET`s for the layers after it.
- Pages that render `topcoat::runtime::script()` need `.runtime()` **and** `.assets(...)`, or they panic.
- `.app_context(T)` twice with the same type panics; wrap in newtypes (`PrimaryDb(Db)`).
- Discovered layers need unique paths; stack several on one path with explicit `.layer(...)`.
- `build()` panics if a layer path matches no route: fix the path, it was dead code.
- `topcoat::start` binds `HOST`/`PORT` and handles Ctrl+C/`SIGTERM` (30s drain). For custom listeners or timeouts:

```rust
use std::time::Duration;
use topcoat::router::{Router, RouterService};

pub async fn serve_custom(router: Router) -> std::io::Result<()> {
    let listener = tokio::net::TcpListener::bind(("0.0.0.0", 8080)).await?;
    let service = RouterService::new(router).shutdown_timeout(Duration::from_secs(10));
    topcoat::serve_until(listener, service, async {
        let _ = tokio::signal::ctrl_c().await;
    })
    .await
}
```

Hardening knobs (defaults are safe; change deliberately):

```rust
use topcoat::{
    router::{BodyLimit, OriginPolicy, Router, RouterBuilder, TrailingSlash, TrustedProxies},
    view::{RouterSuspenseExt, SuspenseMode},
};

pub fn hardened(builder: RouterBuilder) -> Router {
    builder
        // Default rejects cross-origin state-changing requests + WS handshakes (403).
        .origin_policy(OriginPolicy::new().exempt_paths(["/webhooks/{*rest}"]))
        // client_ip(cx) trusts forwarding headers only from these proxies.
        .trusted_proxies(TrustedProxies::new().networks(["10.0.0.0/8"]))
        // Default: 308 to the declared form. Serve = both, Strict = 404.
        .trailing_slash(TrailingSlash::Redirect)
        // Buffered bodies cap at 2 MiB by default (413).
        .layer(BodyLimit::max(32 * 1024 * 1024).at("/upload"))
        .suspense(SuspenseMode::Stream)
        .build()
}
```

Response compression is on by default (`compression` feature).

## 4. Pages, layouts, routes

Every page, layout, component, and shard returns `Result<impl View>` and wraps the view in `Ok(...)`. A page that only redirects returns `Result<()>`.

```rust
use serde::Deserialize;
use topcoat::{
    Result,
    context::Cx,
    cookie::{Cookie, Cookies, cookies},
    router::{
        Slot, StatusCode,
        content::Form,
        error::{NotFoundError, SeeOther, see_other},
        href, layout, not_found, page, route,
    },
    view::{View, class, error_boundary, view},
};

use crate::context::current_user;

// Branded 404s for URLs no route matches (unmatched URLs skip layouts otherwise).
not_found!();

// src/app.rs: wraps every page.
#[layout]
async fn shell(cx: &Cx, slot: Slot<'_>) -> Result<impl View> {
    Ok(view! {
        <!DOCTYPE html>
        <html lang="en">
            <head>
                <meta charset="utf-8">
                <title>"Pastel"</title>
                topcoat::dev::script()      // live reload under `topcoat dev`
                topcoat::runtime::script()  // signals, shards, procedures, push
            </head>
            <body>
                <nav>
                    <a
                        let link = href!(posts::page);
                        let current = link.is_current(cx);
                        href=(link)
                        aria-current=(current.then_some("page"))
                        class=(class!("nav-link", "active" if current))
                    >
                        "Posts"
                    </a>
                    match current_user(cx).await {
                        Some(user) => <span>"Hi, " (&user.name)</span>,
                        None => "",
                    }
                </nav>
                <main>
                    error_boundary(
                        fallback: |error| {
                            if error.downcast_ref::<NotFoundError>().is_none() {
                                return Err(error); // rethrow everything else
                            }
                            Ok(view! {
                                (StatusCode::NOT_FOUND)
                                <h1>"Page not found"</h1>
                            })
                        },
                        (slot)
                    )
                </main>
            </body>
        </html>
    })
}

// src/app.rs -> GET /
#[page]
async fn page() -> Result<impl View> {
    Ok(view! {
        <h1>"Home"</h1>
        <form method="post" action=(href!(sign_in))>
            <input name="name" required="">
            <button type="submit">"Sign in"</button>
        </form>
    })
}

#[derive(Deserialize)]
struct SignIn {
    name: String,
}

// src/app.rs -> POST /sign-in  ("./" joins onto the module path)
#[route(POST "./sign-in")]
async fn sign_in(cx: &Cx, Form(form): Form<SignIn>) -> Result<SeeOther> {
    cookies(cx).add(
        Cookie::build(("user", form.name.trim().to_owned()))
            .path("/")
            .http_only(true)
            .build(),
    );
    Ok(see_other(href!(page).resolve(cx)))
}
```

Health (liveness) route — module-derived, `src/app/health.rs` -> `GET /health`:

```rust
use topcoat::{Result, router::route};

#[route(GET)]
async fn health() -> Result<&'static str> {
    Ok("ok")
}
```

Path forms:
- No string: path from the module (`module_router!` only).
- `"./x"`: below the module path, still module-routed. `"./"` adds a trailing slash.
- `"/abs"`: explicit; registered by `.discover()` or `.page(name)`, not the module router.
- Methods: `#[route(GET)]`, `#[route([GET, POST] "/form")]`, `#[route(* "/hook")]`, `#[page(POST "./export")]`.
- `href!(handler, ParamType(v))` builds URLs; `.resolve(cx)` for a `String`; `.query(..)`, `.fragment(..)`, `.absolute()`; `.is_current(cx)` for nav state.

Path and query params (`src/app/posts/post_id.rs` -> `/posts/{post_id}`):

```rust
use topcoat::{
    Result,
    context::Cx,
    router::{error::RouterErrorExt, page, path_param, query_params},
    view::{View, view},
};

use crate::{context::db, models::Post};

path_param!(pub post_id: u64, error = not_found);

#[query_params(error = bad_request)]
struct PostQuery {
    preview: Option<bool>, // empty value (`?preview=`) reads as None
}

#[page]
pub async fn page(cx: &Cx) -> Result<impl View> {
    let id = *path_param::<PostId>(cx)?;
    let query = query_params::<PostQuery>(cx)?;
    let post = Post::filter_by_id(id)
        .first()
        .exec(&mut db(cx))
        .await?
        .ok_or_not_found()?;

    Ok(view! {
        <h1 data-preview=(query.preview.unwrap_or(false))>(&post.title)</h1>
    })
}
```

**Gotchas (hit while verifying):**
- `#[page] async fn page` (and every handler macro) defines a unit struct with the function's name in that module. A local `let page = ...` then fails with "interpreted as a unit struct". Name locals `page_no`, `current_page`, etc.
- A root `not_found!()` registers `/{*rest}`. A `path_param!` module directly under the root (`/{id}`) conflicts with it and `build()` panics with `conflicts with registered route`. Nest params under a static segment (`/posts/{post_id}`).
- Module-derived handlers (no path string) do not implement `Route`: `.route(health)` fails to compile. They are only registered through `module_router!()`.

## 5. Views and components

```rust
use topcoat::{
    Result,
    context::Cx,
    router::href,
    view::{Child, View, ViewExt, attributes, component, view},
};

#[component]
async fn panel(#[into] title: String, #[default] child: Child<'_>) -> Result<impl View> {
    Ok(view! {
        <section class="panel">
            <h2>(title)</h2>
            (child)
        </section>
    })
}

#[component]
async fn post_list(cx: &Cx) -> Result<impl View> {
    let posts = published_posts(cx).await?;
    Ok(view! {
        panel(
            title: "Posts",
            <ul>
                #[key(post.id)]
                for post in posts {
                    <li id=(format!("post-{}", post.id))>
                        <a href=(href!(post_id::page, post_id::PostId(post.id)))>(&post.title)</a>
                    </li>
                }
            </ul>
        )
    })
}

// Recursive (or multi-return) components box the view.
#[component]
async fn countdown(n: u32) -> Result<impl View> {
    Ok(view! {
        <li>(n)</li>
        if n > 0 {
            countdown(n: n - 1)
        }
    }
    .boxed())
}
```

**Rules:**
- Text is quoted (`"Hi"`); Rust goes in parens (`(user.name)`); void elements have no close tag.
- Control flow: `if`/`else`, `for`, `match` (arm = one node; wrap siblings in `{ }`), `let` — in children and attribute lists.
- Booleans: `disabled=(flag)` omits when false; `title=(Option)` omits on `None`; literal `required=""` always present. Enumerated attrs (`aria-expanded`) take `"true"`/`"false"` strings.
- `class!("base", "active" if cond)`; `attributes! { id="x" @click=$(...) }` for forwarding attrs (e.g. `attrs:` on UI components).
- Views are **lazy and move-capture** like `async move`: clone before reuse; unused views never run.
- Components in one view render **concurrently**; bodies must be side-effect free and order-independent. A `for` over components fires every iteration's I/O at once: bound untrusted lists.
- `#[key(expr)]` on loops that render components, live regions, or signals; unkeyed identity errors when consumed. For helpers called per item pass `&cx.keyed(item.id)`.
- `(StatusCode::X)` and `((header::NAME, HeaderValue::from_static(..)))` in node position set response status/headers; first wins; in a layout put them before `(slot)` to override, after to default.
- Outside components: `view! { cx => ... }` / `live! { cx => ... }`.

## 6. Request context — functions, not middlewares

Model auth, DB access, tenancy, locale as small `cx: &Cx` functions called where needed. Memoize the expensive ones. No middleware ordering, no prop drilling.

```rust
use toasty::Db;
use topcoat::{
    Result,
    context::{Cx, app_context, memoize},
    cookie::{Cookies, cookies},
    router::error::{RouterErrorExt, UnauthorizedError},
};

use crate::models::Post;

/// Cheap clone of the pooled handle; Toasty statements need `&mut Db`.
pub fn db(cx: &Cx) -> Db {
    app_context::<Db>(cx).clone()
}

#[derive(Debug, Clone)]
pub struct User {
    pub name: String,
    pub admin: bool,
}

/// Resolved once per request, shared by every caller.
#[memoize(as_ref)]
pub async fn current_user(cx: &Cx) -> Option<User> {
    let name = cookies(cx).get("user")?.value().trim().to_owned();
    (!name.is_empty()).then(|| User { admin: name == "admin", name })
}

pub async fn require_auth(cx: &Cx) -> Result<&User, UnauthorizedError> {
    current_user(cx).await.ok_or_unauthorized()
}

pub async fn require_admin(cx: &Cx) -> Result<&User> {
    let user = require_auth(cx).await?;
    Ok(user.admin.then_some(user).ok_or_forbidden()?)
}

/// One query per request, however many components ask.
#[memoize(as_ref)]
async fn query_published_posts(cx: &Cx) -> Result<Vec<Post>> {
    let posts = Post::filter(Post::fields().published().eq(true))
        .order_by(Post::fields().id().desc())
        .exec(&mut db(cx))
        .await?;
    Ok(posts)
}

/// `topcoat::Error` is cheap to clone (0.9+), so shared failures clone out.
pub async fn published_posts(cx: &Cx) -> Result<&Vec<Post>> {
    query_published_posts(cx).await.map_err(Clone::clone)
}
```

**Rules:**
- `#[memoize]` returns `&T`; `#[memoize(as_ref)]` returns `Option<&T>` / `Result<&T, &E>`. Arguments need only `Hash` (derived `Hash` is safe; a hand-written one that skips fields collides).
- Memoize is per request and scope-aware (`cx.with(..)` values it reads are part of the key). Same-argument recursion panics.
- `app_context::<T>` panics if unregistered: wrap it (`db(cx)`); use `try_app_context` for optional values.
- `Cx` is immutable: `cx.with(value)` / `cx.with_many((a, b))` derive child scopes; read via `request_context::<T>` / `try_request_context::<T>`.
- Work outliving the handler (`tokio::spawn`, streams, WS loops) moves a `cx.clone()`; it cannot change sent headers or cookies.
- Request helpers: `topcoat::router::request::{headers, method, uri, parts, client_ip, remote_addr, original_uri}`.

## 7. Errors

- Handlers return `topcoat::Result<T>`; any `std::error::Error` converts with `?`. Unhandled non-router errors → **500 with no message leak**.
- Router errors pick the status: `not_found()`, `bad_request(msg)` (message is client-visible), `unauthorized()`, `forbidden()`, `redirect(uri)`, `redirect_permanent`, `see_other`, `too_many_requests(secs)`, `service_unavailable(secs)`, `content_too_large()`, `internal_server_error(e)` (records the source, still 500).
- `RouterErrorExt`: `.ok_or_not_found()`, `.ok_or_unauthorized()`, `.ok_or_forbidden()`, `.ok_or_bad_request(msg)`, `.ok_or_redirect(uri)` on `Option`/`Result`.
- Map domain errors at the edge: `match e { Domain::Missing => not_found().into(), other => other.into() }`.
- Catch with `error_boundary(fallback: |error| ..., child)`; downcast, add `(StatusCode::X)` (else 200), return `Err(error)` to rethrow.
- `Error::context("msg")`, `Error::msg(..)`, `downcast_ref`, `downcast_cloned`. anyhow: enable the `anyhow` feature, `Error::from_anyhow(e)`.
- Rewrites (invisible re-dispatch): `Err(rewrite("/settings", Body::empty()).method(Method::GET).with(Saved).into())`; read with `try_request_context::<Saved>(cx)`; `original_uri(cx)` sees the client URL. Max 8 hops; cycles → 500.

## 8. Forms and Post/Redirect/Get with Toasty

```rust
use serde::Deserialize;
use topcoat::{
    Result,
    context::Cx,
    router::{content::Form, error::{SeeOther, see_other}, href, route},
};

use crate::{context::{db, require_admin}, models::Post};

#[derive(Deserialize)]
struct NewPost {
    title: String,
}

// src/app/posts.rs -> POST /posts
#[route(POST)]
async fn create(cx: &Cx, Form(input): Form<NewPost>) -> Result<SeeOther> {
    require_admin(cx).await?;
    let title = input.title.trim();
    if !title.is_empty() {
        toasty::create!(Post { title, published: true })
            .exec(&mut db(cx))
            .await?;
    }
    Ok(see_other(href!(page).resolve(cx)))
}
```

- A **page** answering a POST returns `Err(see_other(uri).into())` (its `Ok` is a view).
- Updates: `toasty::update!(post { published: false }).exec(&mut db).await?`; atomic `login_count.increment()` needs Toasty 0.9+.
- Toasty (separate crate, pin latest): `#[derive(toasty::Model)]` with `#[key] #[auto] id`, `#[unique]`, `#[index]`, `#[has_many]`/`#[belongs_to]` with `toasty::Deferred<_>`, `#[document]` JSON fields (0.9+), enum embeds with `#[shared(id)]` for polymorphic relations (0.9+). `sqlite::memory:` caps the pool at 1 connection.
- Other bodies: `Json<T>` in/out, `RawForm`, `Bytes`, `Multipart` (`multipart` feature). One body parameter per handler.

## 9. Streaming SSR — `live!`, `suspense`, `error_boundary`

```rust
use std::time::Duration;
use topcoat::view::{View, component, emit, error_boundary, live, suspense, view};

// Region: first emission ships with the document, later ones swap in place.
Ok(view! {
    <h1>(&post.title)</h1>
    (live! {
        emit! { <p>"Computing stats..."</p> }?;
        tokio::time::sleep(Duration::from_millis(200)).await;
        emit! { <p>"Stats ready for post " (id)</p> }
    })
})

// Prepackaged shapes compose: failure is contained, slowness streams.
Ok(view! {
    error_boundary(
        fallback: |error| Ok(view! { <p>"Posts unavailable: " (error.to_string())</p> }),
        suspense(fallback: view! { <p>"Loading..."</p> }, post_list())
    )
})
```

**Rules:**
- Start a `live!` body with something ready immediately; the page waits for the first emission.
- The body returns `Result<EmitToken>`; end with `emit!` or `Ok(EmitToken)` (must still emit at least once).
- `match emit! { widget() } { Err(e) => emit! { ... }, ok => ok }` renders a fallback in place.
- `SuspenseMode::Wait` (per boundary, per request context, or `.suspense(..)` on the router) renders without JS/fallback.
- Once the first byte is sent the response is **committed**: later status codes/headers are ignored, redirects become client-side navigation, errors need a boundary, and **cookie writes panic** — set cookies/sessions before streaming.
- Timing layers measure time to headers, not to the last streamed chunk.

## 10. Client runtime — signals, `$(...)`, `@`, `:`

```rust
use topcoat::{
    Result,
    context::Cx,
    router::page,
    runtime::{Event, expr, signal},
    view::{View, view},
};

#[page]
async fn page(cx: &Cx) -> Result<impl View> {
    let open = signal(cx, || false);
    let count = signal(cx, || 0usize);
    let label = expr!(if count.get() > 10 { "Plenty" } else { "Keep going" });

    Ok(view! {
        <button @click=$(|_e| open.toggle())>"What is Topcoat?"</button>
        <p :hidden=$(!open.get())>"A full-stack Rust framework."</p>
        <button @click=$(|_e| count.increment())>"+1"</button>
        <p>$(count.get()) " - " (label)</p>
    })
}
```

- `signal(cx, || init)` needs `cx: &Cx`; initial value computed on the server, then browser-owned. Pass to components as `&Signal<T>`.
- `$(...)` runs on the server for first paint and as JS in the browser — no round trip. `@event=$(|e: Event| ...)` handlers, `:attr=$(...)` bindings, `:value` + `@input` for two-way inputs.
- Vocabulary only: integers (unsuffixed literal = `usize`, operands same type, overflow panics), `f64`, `bool`, `String`/`&str` basics, `Option`, `Result`, `Vec`/arrays/slices, tuples; `if`, blocks, closures, `async`/`.await`, loops. Anything else → `raw!("js ${x}", rust_equiv)` or a JS string attr `@click="..."`.
- Shorthands: `toggle`, `increment`, `decrement`, `push_str`, `get`, `set`.
- Captured values are **snapshots** and must be vocabulary types: bind fields first (`let id = post.id;` then `$(async |_e| { like(id).await; })`), clone strings the closure needs.
- **Every signal value coming back from the browser is user input.** Validate/clamp before use.

## 11. Shards and procedures

Tracked read in a page → whole page reruns on the server and morphs in (focus/input preserved). Draw a `#[shard]` boundary when a rerun does too much work.

```rust
use topcoat::{
    Result,
    context::Cx,
    router::page,
    runtime::{Event, procedure, shard, signal},
    view::{View, view},
};

#[page]
async fn page(cx: &Cx) -> Result<impl View> {
    let query = signal(cx, String::new);
    // Tracked server read: page reruns on change. Browser input — cap it.
    let q: String = query.get().trim().chars().take(64).collect();

    Ok(view! {
        <input :value=$(query.get()) @input=$(|e: Event| query.set(e.target.value))>
        <p>"Searching for: " (q)</p>
        results(needle: $(query.get()))
        pager()
    })
}

// Stable public endpoint: POST /search/results. Authorize + validate inside.
#[shard("/search/results")]
async fn results(cx: &Cx, needle: String) -> Result<impl View> {
    let needle = needle.trim().to_lowercase();
    let posts = published_posts(cx).await?;
    Ok(view! {
        <ul>
            #[key(post.id)]
            for post in posts.iter().filter(|p| p.title.to_lowercase().contains(&needle)) {
                <li id=(format!("result-{}", post.id))>(&post.title)</li>
            }
        </ul>
    })
}

// Shard-owned state: only this shard reruns; the signal survives reruns.
#[shard]
async fn pager(cx: &Cx) -> Result<impl View> {
    let page_no = signal(cx, || 1usize);
    let current = page_no.get().clamp(1, 100);
    Ok(view! {
        <p>"Page " (current)</p>
        <button @click=$(|_e| { if page_no.get() > 1 { page_no.decrement() } })>"prev"</button>
        <button @click=$(|_e| page_no.increment())>"next"</button>
    })
}

#[procedure("/api/posts/like")]
async fn like(cx: &Cx, post_id: u64) -> Result<bool> {
    require_auth(cx).await?;
    // ... validate post_id, write through db(cx)
    Ok(true)
}

// Call from a handler: @click=$(async |_e| { let ok = like(id).await; liked.set(ok); })
```

**Rules:**
- Shards and procedures are **public HTTP endpoints**. Page/layout guards do **not** run for them: call `require_auth(cx)` and validate every argument inside.
- `.get()`/`.read()` in plain Rust = tracked; `.get_untracked()`/`.read_untracked()` = no rerun. Reads inside `$(...)` never track.
- `Signal<T>` shard parameter passes the handle (`limit: $(limit)` or `limit`); only tracked reads in the shard body cause reruns.
- Morph matches by position + tag, pinned by `id`: give reorderable items stable `id`s. Coalesced per tick; newest request wins.
- Procedure call in `$(...)` must be browser-only (inside an event closure); server evaluation panics. `Err` fails the browser expression — return `Result<T, String>` as data if the client must handle it.
- Arguments/returns must be in the expression vocabulary. Default endpoint paths change between builds; pass `"/abs"` for stable ones (no params). Register with `.discover()` or `.route(name)`.

## 12. Server push over WebSocket (0.9+)

```rust
use std::sync::Mutex;
use tokio::sync::broadcast;
use topcoat::{
    Result,
    context::{Cx, app_context},
    runtime::{connected, shard},
    view::{View, emit, live},
};

#[shard]
async fn chat_box(cx: &Cx) -> Result<impl View> {
    Ok(live! {
        let chat = app_context::<Chat>(cx);
        // Subscribe before reading so no message slips between read and wait.
        let mut changed = chat.subscribe();
        loop {
            let token = emit! {
                <ul>
                    for message in chat.messages() {
                        <li>(message)</li>
                    }
                </ul>
            }?;
            // HTTP render: emit once and finish. Connected render: keep pushing.
            if !connected(cx) {
                break Ok(token);
            }
            changed.recv().await.ok();
        }
    })
}

pub struct Chat {
    messages: Mutex<Vec<String>>,
    changed: broadcast::Sender<()>,
}

impl Chat {
    fn messages(&self) -> Vec<String> {
        self.messages.lock().map(|m| m.clone()).unwrap_or_default()
    }

    fn subscribe(&self) -> broadcast::Receiver<()> {
        self.changed.subscribe()
    }

    pub fn send(&self, message: String) {
        if let Ok(mut messages) = self.messages.lock() {
            messages.push(message);
        }
        let _ = self.changed.send(()); // no subscribers is fine
    }
}

impl Default for Chat {
    fn default() -> Self {
        Self { messages: Mutex::new(Vec::new()), changed: broadcast::channel(16).0 }
    }
}
```

- Needs `.runtime()`, the asset bundle, and `topcoat::runtime::script()` in `<head>`.
- The body runs from the top on HTTP render and again on every (re)connect: read current state each run; keep indefinite waits behind `connected(cx)`.
- Start long jobs elsewhere (app context / spawned task) and observe them here, or reconnects restart them.
- `connected_untracked(cx)` reads the flag without requesting a socket.
- Behind proxies, allow WebSocket upgrades on the app host; the origin policy rejects cross-origin handshakes.

## 13. Observability layer (UUID v7 request IDs)

Topcoat ships no tracing. Add one root layer; it is discovered by `.discover()`.

```rust
use std::time::Instant;
use topcoat::{
    Result,
    context::{Cx, try_request_context},
    router::{
        Body, HeaderName, HeaderValue, Next, layer,
        request::{method, uri},
        response::{Response, response_headers},
    },
};
use tracing_subscriber::EnvFilter;
use uuid::Uuid;

pub fn init() {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .init();
}

#[derive(Clone, Copy)]
pub struct RequestId(pub Uuid);

pub fn request_id(cx: &Cx) -> Option<Uuid> {
    try_request_context::<RequestId>(cx).map(|id| id.0)
}

#[layer("/")]
async fn trace_requests(cx: &Cx, body: Body, next: Next<'_>) -> Result<Response> {
    let id = Uuid::now_v7();
    let started = Instant::now();

    // Queued headers land on success *and* error responses.
    if let Ok(value) = HeaderValue::from_str(&id.to_string()) {
        response_headers(cx).append(HeaderName::from_static("x-request-id"), value);
    }

    let cx = cx.with(RequestId(id));
    let result = next.run(&cx, body).await;

    let elapsed_ms = u64::try_from(started.elapsed().as_millis()).unwrap_or(u64::MAX);
    match &result {
        Ok(response) => tracing::info!(
            request_id = %id,
            method = %method(&cx),
            path = uri(&cx).path(),
            status = response.status().as_u16(),
            elapsed_ms,
            "request"
        ),
        Err(error) => tracing::warn!(request_id = %id, %error, elapsed_ms, "request failed"),
    }
    result
}
```

`#[layer]` layers wrap matched routes only (404/405 skip them); for truly every request implement `Layer` with `path() -> None`. Tower middleware: `tower` feature + `TowerLayer::new(layer).at("/api")`.

## 14. Cookies, sessions, assets, Tailwind, UI

- Cookies: `.cookies()` on the router; `cookies(cx).get/add/remove`; `cookie! { NAME = v; Path = "/"; HttpOnly; SameSite = Lax; MaxAge = Duration::days(30) }`. Signed/private jars and `CookieStore<T>` exist. Writes survive error/redirect responses (0.8.1+) but panic after streaming starts.
- Sessions: `.cookies().sessions(SessionConfig::default())`; `session::start(cx)` on login (persist `token_hash` + `expires_at`, never the raw token), `session::token_hash(cx)` to resolve, `stop`, `refresh`, `rotate`. Wrap in `current_user(cx)`.
- Assets: `const LOGO: Asset = asset!("./logo.svg");` → `<img src=(LOGO)>` renders a content-hashed URL. Only handles that stay in the binary are bundled. `AssetBundle::load()` reads `target/<profile>/assets`; bundle with the same profile you run. CDN: `AssetConfig::hosted_at(url, manifest)`.
- Tailwind: `tailwind` feature in `[dependencies]` **and** `[build-dependencies]` (`default-features = false`), `build.rs` → `topcoat::tailwind::BuildConfig::new().input("styles.css").render().unwrap()`, `<link rel="stylesheet" href=(tailwind::stylesheet!())>`.
- UI: `ui` feature, `topcoat ui init`, `topcoat ui add button card dialog sidebar field`, commit `components.toml` + `styles.css`, `topcoat ui update` after upgrades. Components are yours to edit.
- Static dirs: `fs` feature, `.public_dir("./public")`, `.serve_dir("/downloads/{*file}", "./files")`.
- Fonts/icons: `font-fontsource` (`fontsource_font!(GEIST, host: Asset)`), `icon-iconify`.

## 15. Testing

Dispatch through `Router::handle` — no port. Reuse `routes(db)`; pages under a layout that renders `runtime::script()` also need `.runtime()` and a bundle, so run `topcoat asset bundle` before `cargo test`.

```rust
#[cfg(test)]
mod tests {
    use toasty::Db;
    use topcoat::{
        asset::{AssetBundle, RouterBuilderAssetExt},
        router::{Body, Router, to_bytes},
        runtime::RouterBuilderRuntimeExt,
    };

    async fn test_db() -> Db {
        let db = Db::builder()
            .models(toasty::models!(crate::*))
            .connect("sqlite::memory:")
            .await
            .expect("db");
        db.push_schema().await.expect("schema");
        db
    }

    /// `topcoat asset bundle` writes `target/<profile>/assets`; tests run from `deps/`.
    fn test_assets() -> AssetBundle {
        let exe = std::env::current_exe().expect("test exe");
        let dir = exe.parent().and_then(|deps| deps.parent()).expect("target dir").join("assets");
        AssetBundle::load_dir(dir).expect("run `topcoat asset bundle` before `cargo test`")
    }

    async fn test_router() -> Router {
        super::routes(test_db().await).assets(test_assets()).runtime().build()
    }

    async fn send(router: &Router, method: &str, path: &str, body: &str) -> (u16, String) {
        let mut request = http::Request::builder().method(method).uri(path);
        if !body.is_empty() {
            request = request.header("content-type", "application/x-www-form-urlencoded");
        }
        let request = request.body(Body::from(body.to_owned())).expect("valid request");
        let response = router.handle(request).await;
        let status = response.status().as_u16();
        let bytes = to_bytes(response.into_body(), usize::MAX).await.expect("body");
        (status, String::from_utf8_lossy(&bytes).into_owned())
    }

    #[tokio::test]
    async fn health_is_ok() {
        let router = super::routes(test_db().await).build(); // routes need no bundle
        assert_eq!(send(&router, "GET", "/health", "").await, (200, "ok".to_owned()));
    }

    #[tokio::test]
    async fn missing_post_uses_branded_404() {
        let (status, body) = send(&test_router().await, "GET", "/posts/999", "").await;
        assert_eq!(status, 404);
        assert!(body.contains("Page not found"));
    }

    #[tokio::test]
    async fn create_post_requires_auth() {
        let (status, _) = send(&test_router().await, "POST", "/posts", "title=hi").await;
        assert_eq!(status, 401);
    }
}
```

- Module-derived handlers (no path string) do not implement `Route`; test them through `module_router!()` (`routes(db)`), not `.route(name)`.
- Explicit-path handlers can be tested in isolation: `Router::builder().page(home).build()`.
- `Router::handle_with(request, (Value,))` seeds request context. Mail: `MemoryTransport` captures sends.
- Streamed pages include swap `<template>`/`<script>` chunks after `</html>`; assert on content, not exact markup.
- Panics inside a request become 500s (isolated), so assert status codes.

## 16. Code quality checklist

### Handlers and views
- Every page/layout/component/shard: `-> Result<impl View>` + `Ok(view! { .. })`; no `?` after `view!`.
- No side effects in component bodies or template expressions; do ordered work before building the view.
- `#[key(..)]` on loops with components, signals, or live regions; stable `id` on reorderable DOM.
- No local bindings that shadow handler names in the same module (`page`, `layout`, ...).
- `href!` for internal links, never hand-written paths.

### Security
- Validate + authorize inside every `#[shard]`, `#[procedure]`, and on every tracked signal read.
- Keep the default `OriginPolicy`; exempt only webhooks that verify signatures.
- `bad_request(msg)` text is public; never include internals. Unhandled errors already hide messages.
- Raise `BodyLimit` only per path (`.at("/upload")`).
- Configure `TrustedProxies` before relying on `client_ip(cx)`.
- Session tokens: store `TokenHash`, not tokens; `rotate` on privilege change.

### Streaming
- Cookies, sessions, status, headers set before the first streamed byte.
- `error_boundary` around streamed content that can fail.
- Indefinite waits only after `if !connected(cx) { break Ok(token); }`.

### Operations
- `topcoat-cli` version == `topcoat` version; `topcoat asset bundle --release` for release builds.
- `tracing` only (no `println!`); UUID v7 request IDs via the root layer.
- No `unwrap()` outside tests; `expect("why")` for startup invariants (asset bundle).
- `topcoat fmt && cargo fmt && cargo clippy --all-targets -- -W clippy::pedantic && cargo test`.

## Cargo.toml essentials

```toml
[package]
edition = "2024"
rust-version = "1.98"

[dependencies]
topcoat = "0.9"                    # features: tailwind, ui, font-fontsource, mail, websocket, sse, tower, fs, anyhow
tokio = { version = "1", features = ["rt-multi-thread", "macros", "sync", "time"] }
serde = { version = "1", features = ["derive"] }
toasty = { version = "0.11", features = ["sqlite"] }
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
uuid = { version = "1", features = ["v7"] }

[build-dependencies]               # only with Tailwind
# topcoat = { version = "0.9", default-features = false, features = ["tailwind"] }

[dev-dependencies]
http = "1"
```
