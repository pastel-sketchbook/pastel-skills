---
name: ps-axum-patterns
version: 1.1.0
rust_version: v1.95.0
description: |
  Common patterns for building Axum web services in Pastel Sketchbook Rust
  projects — app/router composition, Arc<AppState> with atomics, tower-http
  tracing layer, health/ready endpoints, error handling with thiserror+anyhow,
  config from env, graceful shutdown, OpenAPI with utoipa, handler testing via
  tower::oneshot, and integration tests with random ports.
  Use when scaffolding a new Axum service, adding routes, wiring shared state,
  implementing health checks, or setting up structured error handling.
---

# Axum Web Service Patterns

Battle-tested patterns for Pastel Sketchbook Axum apps — copy, adapt, do **not** reinvent.

## When to use

Reach for this skill whenever the task touches:

- scaffolding a new Axum HTTP service,
- composing routers with nested or merged sub-routers,
- wiring shared application state,
- adding health/ready/metrics endpoints,
- handling errors in handlers or domain code,
- loading configuration from environment variables,
- adding OpenAPI documentation,
- writing handler or integration tests.

## 1. Project structure

Separate lib from binary. The library exposes `AppState`, the router builder, and all modules. The binary is a thin orchestrator.

```
src/
  main.rs        # Thin entry: config, init, serve, shutdown
  lib.rs         # Module declarations, public app() builder
  config.rs      # Typed config from env vars
  error.rs       # thiserror enums for domain errors
  health.rs      # Health/ready router + handlers
  routes/        # One module per resource domain (optional)
    mod.rs
    items.rs
  middleware.rs  # Custom middleware (optional)
  telemetry.rs   # Tracing/OTLP init (optional)
```

Keep `main.rs` minimal — just wiring:

```rust
use anyhow::{Context, Result};

#[tokio::main]
async fn main() -> Result<()> {
    let config = Config::from_env()?;
    init_tracing();

    let state = Arc::new(AppState::new(&config).await?);
    let app = my_crate::app(state);

    let listener = tokio::net::TcpListener::bind(&config.listen_addr)
        .await
        .context("bind")?;

    tracing::info!(addr = %config.listen_addr, "listening");
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await
        .context("serve")?;

    Ok(())
}

async fn shutdown_signal() {
    tokio::signal::ctrl_c().await.ok();
    tracing::info!("shutting down");
}
```

## 2. Router composition

Build routers as functions returning `Router`. Merge or nest them in `app()`.

```rust
use axum::{Router, routing::get};
use std::sync::Arc;

pub fn app(state: Arc<AppState>) -> Router {
    let api = Router::new()
        .route("/items", get(list_items).post(create_item))
        .route("/items/{id}", get(get_item).delete(delete_item));

    Router::new()
        .route("/health", get(health))
        .route("/ready", get(ready))
        .nest("/api", api)
        .layer(tower_http::trace::TraceLayer::new_for_http())
        .with_state(state)
}
```

**Rules:**
- `.with_state(state)` goes last.
- `.layer(...)` applies to all routes above it in the same router.
- Use `.merge(other_router)` for peer-level composition.
- Use `.nest("/prefix", sub_router)` for path-prefixed groups.
- Feature-gate optional routers with `#[cfg(feature = "...")]`.

## 3. Application state

Use `Arc<AppState>` with atomics for metrics and health flags. Avoid `Mutex` for simple counters.

```rust
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;

pub struct AppState {
    pub db: Database,
    pub healthy: AtomicBool,
    pub request_count: AtomicU64,
}

impl AppState {
    pub fn new(db: Database) -> Self {
        Self {
            db,
            healthy: AtomicBool::new(true),
            request_count: AtomicU64::new(0),
        }
    }
}
```

For complex shared structures (HashMaps, ring buffers), use `tokio::sync::RwLock` or `tokio::sync::Mutex` inside the `Arc`.

## 4. Health and readiness endpoints

Always provide `/health` (liveness) and `/ready` (readiness). Return JSON with `StatusCode`.

```rust
use axum::{extract::State, http::StatusCode, Json};
use serde::Serialize;
use std::sync::Arc;

#[derive(Serialize)]
struct HealthResponse {
    status: &'static str,
}

pub async fn health() -> impl axum::response::IntoResponse {
    (StatusCode::OK, Json(HealthResponse { status: "ok" }))
}

pub async fn ready(State(state): State<Arc<AppState>>) -> impl axum::response::IntoResponse {
    if state.healthy.load(std::sync::atomic::Ordering::Relaxed) {
        (StatusCode::OK, Json(HealthResponse { status: "ready" }))
    } else {
        (StatusCode::SERVICE_UNAVAILABLE, Json(HealthResponse { status: "unavailable" }))
    }
}
```

## 5. Handler pattern

Handlers are standalone async functions. Annotate with `#[tracing::instrument]` and `#[utoipa::path]`.

```rust
#[tracing::instrument(skip(state))]
#[utoipa::path(get, path = "/api/items/{id}", responses((status = 200, body = Item)))]
pub async fn get_item(
    State(state): State<Arc<AppState>>,
    axum::extract::Path(id): axum::extract::Path<i64>,
) -> impl axum::response::IntoResponse {
    match state.db.get_item(id).await {
        Ok(Some(item)) => (StatusCode::OK, Json(item)).into_response(),
        Ok(None) => StatusCode::NOT_FOUND.into_response(),
        Err(e) => {
            tracing::error!(error = %e, "db error");
            (StatusCode::INTERNAL_SERVER_ERROR,
             Json(serde_json::json!({ "error": e.to_string() })))
                .into_response()
        }
    }
}
```

**Extractor ordering** (left to right): `State`, `Path`, `Query`, `HeaderMap`/`TypedHeader`, `Json` (body — must be last).

## 6. Error handling

**Two-level strategy:**
- **Domain/infra errors**: `thiserror` enums with typed variants.
- **Binary top-level**: `anyhow::Result<()>` with `.context()`.

```rust
use thiserror::Error;

#[derive(Debug, Error)]
pub enum AppError {
    #[error("not found")]
    NotFound,
    #[error("database: {0}")]
    Database(String),
    #[error("config: {0}")]
    Config(#[from] ConfigError),
}
```

For richer APIs, implement `IntoResponse` on the error type:

```rust
impl axum::response::IntoResponse for AppError {
    fn into_response(self) -> axum::response::Response {
        let (status, msg) = match &self {
            Self::NotFound => (StatusCode::NOT_FOUND, self.to_string()),
            Self::Database(_) => (StatusCode::INTERNAL_SERVER_ERROR, self.to_string()),
            Self::Config(_) => (StatusCode::INTERNAL_SERVER_ERROR, "config error".into()),
        };
        (status, Json(serde_json::json!({ "error": msg }))).into_response()
    }
}
```

For simple services (health/metrics only), explicit `(StatusCode, Json<T>)` tuples are fine — skip the trait impl.

## 7. Configuration from environment

Parse env vars into a typed `Config` struct. Make it testable by accepting an env-reading function.

```rust
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ConfigError {
    #[error("missing {0}")]
    Missing(String),
    #[error("invalid {0}: {1}")]
    Invalid(String, String),
}

#[derive(Debug)]
pub struct Config {
    pub listen_addr: String,
    pub database_url: String,
}

impl Config {
    pub fn from_env() -> Result<Self, ConfigError> {
        Self::from_env_fn(std::env::var)
    }

    fn from_env_fn<F>(env: F) -> Result<Self, ConfigError>
    where
        F: Fn(&str) -> Result<String, std::env::VarError>,
    {
        Ok(Self {
            listen_addr: env("LISTEN_ADDR").unwrap_or_else(|_| "127.0.0.1:3000".into()),
            database_url: env("DATABASE_URL")
                .map_err(|_| ConfigError::Missing("DATABASE_URL".into()))?,
        })
    }
}
```

**Rules:**
- No `.env` file loaders in production code.
- Validate eagerly at startup — fail fast.
- Use a consistent prefix for app-specific vars (e.g., `CW_*`, `APP_*`).

## 8. Middleware & Context Logging with UUID v7

Use `tower_http::trace::TraceLayer` as the baseline. Add a request-context middleware via `axum::middleware::from_fn` that generates a UUID v7 trace ID per request and injects it into the tracing span so **every log line** within that request carries the correlation ID.

### Why UUID v7

UUID v7 is time-ordered (ms-precision timestamp prefix) — logs sort chronologically by ID, and you can extract the request timestamp from the ID itself without parsing log fields. Prefer it over v4 for any request-scoped correlation ID.

### Middleware implementation

```rust
use axum::{http::Request, middleware::Next, response::Response};
use tracing::Span;
use uuid::Uuid;

/// Newtype stored in request extensions for downstream extraction.
#[derive(Clone, Debug)]
pub struct RequestId(pub String);

pub async fn request_id_middleware(
    mut req: Request<axum::body::Body>,
    next: Next,
) -> Response {
    // Propagate inbound trace ID or generate a new UUID v7.
    let request_id = req
        .headers()
        .get("x-request-id")
        .and_then(|v| v.to_str().ok())
        .map(String::from)
        .unwrap_or_else(|| Uuid::now_v7().to_string());

    // Record in the current tracing span so all downstream logs include it.
    Span::current().record("request_id", &request_id.as_str());

    // Store in extensions for handlers that need programmatic access.
    req.extensions_mut().insert(RequestId(request_id.clone()));

    let mut resp = next.run(req).await;
    resp.headers_mut()
        .insert("x-request-id", request_id.parse().unwrap());
    resp
}
```

### Wiring with TraceLayer

The key is configuring `TraceLayer` to create a span with an empty `request_id` field that the middleware fills in:

```rust
use tower_http::trace::{self, TraceLayer};
use tracing::Level;

pub fn app(state: Arc<AppState>) -> Router {
    Router::new()
        .route("/health", get(health))
        .nest("/api", api_routes())
        .layer(axum::middleware::from_fn(request_id_middleware))
        .layer(
            TraceLayer::new_for_http()
                .make_span_with(|req: &Request<_>| {
                    tracing::info_span!(
                        "http_request",
                        method = %req.method(),
                        uri = %req.uri(),
                        request_id = tracing::field::Empty, // filled by middleware
                    )
                })
                .on_response(trace::DefaultOnResponse::new().level(Level::INFO)),
        )
        .with_state(state)
}
```

**Layer ordering** (added bottom-up, executed top-down):
1. `TraceLayer` — creates the span (outermost, runs first)
2. `request_id_middleware` — fills `request_id` field in the span created above

This means every `tracing::info!`, `tracing::error!`, etc. inside handlers automatically includes `request_id` in structured output:

```json
{"timestamp":"...","level":"INFO","target":"my_app::routes","message":"created item","request_id":"019746a2-...","item_id":42}
```

### Extracting the request ID in handlers

```rust
use axum::Extension;

pub async fn some_handler(
    Extension(req_id): Extension<RequestId>,
    State(state): State<Arc<AppState>>,
) -> impl axum::response::IntoResponse {
    tracing::info!(request_id = %req_id.0, "processing");
    // ...
}
```

Or access it from request extensions without the `Extension` extractor if you already have access to the request.

### Cargo dependency

```toml
uuid = { version = "1", features = ["v7"] }
```

## 9. OpenAPI with utoipa

Register all paths and schemas centrally:

```rust
use utoipa::OpenApi;

#[derive(OpenApi)]
#[openapi(
    paths(health, ready, get_item, list_items, create_item),
    components(schemas(Item, HealthResponse, ErrorResponse))
)]
pub struct ApiDoc;
```

Serve with `utoipa-scalar`:

```rust
use utoipa_scalar::{Scalar, Servable};

router.merge(Scalar::with_url("/docs", ApiDoc::openapi()))
```

## 10. Testing

### Unit tests — tower::oneshot (no server)

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use tower::ServiceExt;

    #[tokio::test]
    async fn health_returns_ok() {
        let state = Arc::new(AppState::new(/* ... */));
        let app = crate::app(state);

        let req = Request::builder()
            .uri("/health")
            .body(Body::empty())
            .unwrap();
        let resp = app.oneshot(req).await.unwrap();

        assert_eq!(resp.status(), StatusCode::OK);
    }
}
```

### Integration tests — real server on random port

```rust
use reqwest::Client;
use tokio::net::TcpListener;

async fn spawn_app() -> String {
    let state = Arc::new(AppState::new(/* test config */));
    let app = my_crate::app(state);

    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();

    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });

    format!("http://127.0.0.1:{port}")
}

#[tokio::test]
async fn test_create_item() {
    let base = spawn_app().await;
    let client = Client::new();

    let resp = client
        .post(format!("{base}/api/items"))
        .json(&serde_json::json!({ "name": "test" }))
        .send()
        .await
        .unwrap();

    assert_eq!(resp.status(), 201);
}
```

### Config tests — mock env function

```rust
#[test]
fn missing_required_var_returns_error() {
    let env = |_: &str| Err(std::env::VarError::NotPresent);
    assert!(Config::from_env_fn(env).is_err());
}

#[test]
fn defaults_applied() {
    let env = |key: &str| match key {
        "DATABASE_URL" => Ok("sqlite://test.db".into()),
        _ => Err(std::env::VarError::NotPresent),
    };
    let cfg = Config::from_env_fn(env).unwrap();
    assert_eq!(cfg.listen_addr, "127.0.0.1:3000");
}
```

## 11. Graceful shutdown

Always use `with_graceful_shutdown`. Pair with `CancellationToken` when background tasks need coordinated shutdown.

```rust
use tokio_util::sync::CancellationToken;

let cancel = CancellationToken::new();
let cancel_clone = cancel.clone();

// Background task respects cancellation
tokio::spawn(async move {
    loop {
        tokio::select! {
            _ = cancel_clone.cancelled() => break,
            _ = do_work() => {}
        }
    }
});

// Server shuts down on ctrl+c, then cancels background tasks
axum::serve(listener, app)
    .with_graceful_shutdown(async move {
        tokio::signal::ctrl_c().await.ok();
        cancel.cancel();
    })
    .await?;
```

## 12. Tracing initialization

```rust
use tracing_subscriber::{fmt, EnvFilter};

pub fn init_tracing() {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .with_target(true)
        .json() // structured JSON for production; remove for dev
        .init();
}
```

For OpenTelemetry, feature-gate behind `otel`:

```rust
#[cfg(feature = "otel")]
pub fn init_otel_tracing() -> Result<()> {
    // opentelemetry-otlp setup
}
```

## 13. Code quality checklist

Review items specific to Axum services. These complement the general Rust rules in the `code-quality-audit` skill.

### Error handling
- **No `unwrap()` in non-test code.** Use `?` with `.context()` or explicit match.
- **`.expect()` only with a safety comment** explaining why the invariant holds.
- **Custom error type implements `IntoResponse`** for non-trivial APIs. Do not leak internal error details (stack traces, SQL errors) in HTTP responses.
- **Use `anyhow::Result<T>` in `main.rs`** and domain code; use `thiserror` for typed errors that cross module boundaries.
- **`anyhow::bail!` for early returns**, `anyhow::ensure!` for preconditions.

### Extractors & handlers
- **Extractor ordering**: `State`, `Path`, `Query`, `HeaderMap`, `Json` (body last).
- **`State` wraps `Arc<AppState>`** — never a raw struct. Flag global mutable state.
- **`#[tracing::instrument(skip(state), err)]`** on every public handler. `skip` large/non-Display args.
- **Structured tracing fields** — `tracing::info!(item_id = %id, "created")` not format strings.
- **No `println!` / `eprintln!`** — use `tracing::*` exclusively.

### Concurrency & async
- **No `Arc<Mutex<>>` held across `.await`.** Use `tokio::sync::Mutex` if a guard must span await points.
- **No blocking I/O in async context.** Flag `std::fs`, `std::net`, `std::thread::sleep` — use tokio equivalents or `spawn_blocking`.
- **`tokio::select!` branches must be cancellation-safe.** Comment each branch.
- **Graceful shutdown wired.** Flag `tokio::main` apps with no signal handling.

### Router & middleware
- **Every non-trivial router has at least one `.layer()` call** (minimum: `TraceLayer`).
- **`.with_state()` applied last** on the router.
- **Feature-gate optional routers** with `#[cfg(feature = "...")]` to keep the binary lean.

### State
- **Prefer atomics** (`AtomicBool`, `AtomicU64`) for health flags and counters.
- **`#[must_use]` on constructors** and functions returning meaningful values.
- **No `lazy_static!`** — use `std::sync::LazyLock` (stable since Rust 1.80).

### Arithmetic safety
- **Saturating arithmetic for counter decrements.** `.saturating_sub()` over `-`.
- **Safe casts.** `as u16` / `as u8` from larger types must be preceded by `.min()` or bounds check.

### Security
- **No hardcoded secrets.** Flag `sk-`, `ghp_`, `AKIA`, `-----BEGIN` patterns.
- **`.env` in `.gitignore`.**
- **No internal error details in responses.** Return generic messages; log the real error server-side.

### Testing
- **Unit tests via `tower::oneshot`** — no running server needed for handler tests.
- **Integration tests bind to port 0** — never hardcode ports.
- **Config tests use mock env function** — no reliance on real environment.

---

## General rule

Always code with the **latest released versions** of all dependencies. Do not pin to outdated versions — check crates.io for the current stable release before adding or updating a dependency.

## Cargo.toml essentials

```toml
[dependencies]
axum = "0.8"
tokio = { version = "1", features = ["full"] }
tower-http = { version = "0.6", features = ["trace"] }
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter", "json"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
thiserror = "2"
anyhow = "1"
utoipa = { version = "5", features = ["axum_extras"] }
utoipa-scalar = { version = "0.2", features = ["axum"] }

[dev-dependencies]
tower = { version = "0.5", features = ["util"] }
reqwest = { version = "0.12", features = ["json"] }
tokio-test = "0.4"
http-body-util = "0.1"
```
