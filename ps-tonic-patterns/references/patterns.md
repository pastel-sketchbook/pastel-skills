# Tonic gRPC Service Patterns — Reference

Patterns for Pastel Sketchbook tonic apps — copy, adapt, do not reinvent.

## 1. Project structure

Separate lib from binaries. The library owns the service implementation and shared types. Binaries are thin orchestrators.

```
src/
  lib.rs             # Module declarations, include_proto!, shared types
  config.rs          # Typed config from env vars
  service.rs         # Trait implementation for the gRPC service
  interceptor.rs     # Auth / logging interceptors
  server/
    main.rs          # Thin binary: config, init, serve, shutdown
  client/
    main.rs          # Client binary (optional)
proto/
  service.proto      # Service definitions
build.rs             # tonic-prost-build code generation
tests/
  integration.rs     # Full transport integration tests
```

## 2. Proto code generation

Single-line `build.rs`:

```rust
fn main() -> Result<(), Box<dyn std::error::Error>> {
    tonic_prost_build::compile_protos("proto/service.proto")?;
    Ok(())
}
```

Include in `lib.rs` with pedantic lints suppressed on generated code:

```rust
pub mod pb {
    #![allow(clippy::pedantic)]
    tonic::include_proto!("my.package");
}
```

**Cargo.toml build-dependencies:**

```toml
[build-dependencies]
tonic-prost-build = "0.14"
```

## 3. Server setup

```rust
use anyhow::{Context, Result};
use std::sync::Arc;
use tokio::net::TcpListener;
use tonic::transport::Server;

#[tokio::main]
async fn main() -> Result<()> {
    let config = Config::from_env()?;
    init_tracing();

    let state = Arc::new(AppState::new(&config).await?);
    let service = MyServiceImpl::new(state.clone());

    let listener = TcpListener::bind(&config.listen_addr)
        .await
        .context("bind")?;

    tracing::info!(addr = %config.listen_addr, "gRPC server listening");

    Server::builder()
        .add_service(my_service_server::MyServiceServer::with_interceptor(
            service,
            auth_interceptor,
        ))
        .add_service(health_service(state))
        .serve_with_incoming_shutdown(
            tokio_stream::wrappers::TcpListenerStream::new(listener),
            shutdown_signal(),
        )
        .await
        .context("serve")?;

    Ok(())
}
```

## 4. Health service for Kubernetes

Use `tonic-health` to expose the standard gRPC health checking protocol. Kubernetes `grpc` liveness/readiness probes hit this directly.

```rust
use tonic_health::server::health_reporter;

pub fn health_service(
    state: Arc<AppState>,
) -> tonic_health::server::HealthServer {
    let (mut reporter, health_service) = health_reporter();

    tokio::spawn(async move {
        reporter
            .set_serving::<my_service_server::MyServiceServer<MyServiceImpl>>()
            .await;

        loop {
            tokio::time::sleep(std::time::Duration::from_secs(5)).await;
            if !state.healthy.load(std::sync::atomic::Ordering::Relaxed) {
                reporter
                    .set_not_serving::<my_service_server::MyServiceServer<MyServiceImpl>>()
                    .await;
            } else {
                reporter
                    .set_serving::<my_service_server::MyServiceServer<MyServiceImpl>>()
                    .await;
            }
        }
    });

    health_service
}
```

**Kubernetes manifest:**

```yaml
livenessProbe:
  grpc:
    port: 50051
  initialDelaySeconds: 5
  periodSeconds: 10
readinessProbe:
  grpc:
    port: 50051
  initialDelaySeconds: 3
  periodSeconds: 5
```

**Cargo.toml:**

```toml
tonic-health = "0.14"
```

## 5. Graceful shutdown

Use `CancellationToken` to coordinate server + background tasks.

```rust
use tokio_util::sync::CancellationToken;

async fn shutdown_signal() {
    tokio::signal::ctrl_c().await.ok();
    tracing::info!("shutdown signal received");
}

// With background tasks:
let cancel = CancellationToken::new();
let cancel_clone = cancel.clone();

tokio::spawn(async move {
    loop {
        tokio::select! {
            _ = cancel_clone.cancelled() => {
                tracing::info!("background task shutting down");
                break;
            }
            _ = do_background_work() => {}
        }
    }
});

Server::builder()
    .add_service(service)
    .serve_with_incoming_shutdown(
        tokio_stream::wrappers::TcpListenerStream::new(listener),
        async move {
            tokio::signal::ctrl_c().await.ok();
            cancel.cancel();
        },
    )
    .await?;
```

Rules:
- Always use `serve_with_incoming_shutdown` or `serve_with_shutdown`.
- Cancel background tasks before returning from main.
- Allow in-flight RPCs to complete (tonic handles this via HTTP/2 GOAWAY).

## 6. Context logging with UUID v7

Inject a request-scoped trace ID into every RPC via an interceptor.

### Interceptor

```rust
use tonic::{Request, Status};
use tracing::Span;
use uuid::Uuid;

#[derive(Clone, Debug)]
pub struct RequestId(pub String);

pub fn request_id_interceptor(mut req: Request<()>) -> Result<Request<()>, Status> {
    let request_id = req
        .metadata()
        .get("x-request-id")
        .and_then(|v| v.to_str().ok())
        .map(String::from)
        .unwrap_or_else(|| Uuid::now_v7().to_string());

    Span::current().record("request_id", &request_id.as_str());
    req.extensions_mut().insert(RequestId(request_id));

    Ok(req)
}
```

### Composing multiple interceptors

Tonic's `with_interceptor` only takes one function. Stack them manually:

```rust
fn combined_interceptor(req: Request<()>) -> Result<Request<()>, Status> {
    let req = request_id_interceptor(req)?;
    let req = auth_interceptor(req)?;
    Ok(req)
}

MyServiceServer::with_interceptor(service, combined_interceptor)
```

### Accessing in handlers

```rust
#[tonic::async_trait]
impl MyService for MyServiceImpl {
    #[tracing::instrument(skip(self, request), err)]
    async fn do_thing(
        &self,
        request: Request<DoThingRequest>,
    ) -> Result<Response<DoThingResponse>, Status> {
        let request_id = request
            .extensions()
            .get::<RequestId>()
            .map(|r| r.0.clone())
            .unwrap_or_default();

        tracing::info!(request_id = %request_id, "processing request");
        // ...
    }
}
```

### Why UUID v7

UUID v7 is time-ordered (ms-precision timestamp prefix) — logs sort chronologically by ID. Prefer over v4 for any request-scoped correlation ID.

## 7. Interceptors (auth pattern)

```rust
use std::sync::LazyLock;
use tonic::{Request, Status};

static AUTH_TOKEN: LazyLock<String> = LazyLock::new(|| {
    std::env::var("AUTH_TOKEN").unwrap_or_else(|_| "secret".into())
});

pub fn auth_interceptor(req: Request<()>) -> Result<Request<()>, Status> {
    let token = req
        .metadata()
        .get("x-auth-token")
        .ok_or_else(|| Status::unauthenticated("missing auth token"))?;

    let token_str = token
        .to_str()
        .map_err(|_| Status::unauthenticated("invalid token encoding"))?;

    if token_str != AUTH_TOKEN.as_str() {
        return Err(Status::unauthenticated("invalid auth token"));
    }

    Ok(req)
}
```

Rules:
- Use `LazyLock` (not `lazy_static!`) for env-based config.
- Return distinct error messages for "missing" vs "invalid".
- Never log the actual token value.

## 8. Error handling

Map domain errors to `tonic::Status` codes:

```rust
use thiserror::Error;
use tonic::Status;

#[derive(Debug, Error)]
pub enum AppError {
    #[error("not found: {0}")]
    NotFound(String),
    #[error("invalid input: {0}")]
    InvalidInput(String),
    #[error("internal: {0}")]
    Internal(String),
}

impl From<AppError> for Status {
    fn from(err: AppError) -> Self {
        match err {
            AppError::NotFound(msg) => Status::not_found(msg),
            AppError::InvalidInput(msg) => Status::invalid_argument(msg),
            AppError::Internal(msg) => {
                tracing::error!(error = %msg, "internal error");
                Status::internal("internal error") // don't leak details
            }
        }
    }
}
```

Usage in handlers:

```rust
async fn get_item(&self, request: Request<GetItemRequest>) -> Result<Response<Item>, Status> {
    let id = request.into_inner().id;
    let item = self.state.db.find(id).await.map_err(|e| AppError::Internal(e.to_string()))?;
    let item = item.ok_or_else(|| AppError::NotFound(format!("item {id}")))?;
    Ok(Response::new(item.into()))
}
```

Rules:
- Never expose internal error details in `Status::internal` messages.
- Use `Status::invalid_argument` for validation failures.
- Log the real error server-side before returning a sanitized Status.
- Use `anyhow::Result` only in `main()` for startup errors.

## 9. Streaming with channels

Server-streaming RPC pattern using `mpsc` + `ReceiverStream`:

```rust
use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;

type ResponseStream = std::pin::Pin<Box<dyn tokio_stream::Stream<Item = Result<MyResponse, Status>> + Send>>;

async fn my_stream(
    &self,
    request: Request<MyRequest>,
) -> Result<Response<ResponseStream>, Status> {
    let (tx, rx) = mpsc::channel(128);

    tokio::spawn(async move {
        for i in 0..10 {
            if tx.send(Ok(MyResponse { value: i })).await.is_err() {
                break; // client disconnected
            }
        }
    });

    Ok(Response::new(Box::pin(ReceiverStream::new(rx))))
}
```

Rules:
- Check `tx.send()` result — break if client disconnected.
- Use bounded channels (`mpsc::channel(n)`) to apply backpressure.
- Spawn the producer task to avoid blocking the handler.

## 10. Configuration

Same pattern as Axum — testable env parsing:

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
    pub auth_token: String,
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
            listen_addr: env("LISTEN_ADDR").unwrap_or_else(|_| "[::]:50051".into()),
            auth_token: env("AUTH_TOKEN")
                .map_err(|_| ConfigError::Missing("AUTH_TOKEN".into()))?,
        })
    }
}
```

Rules:
- Bind to `[::]:50051` (IPv6 any) by default for container compatibility.
- Validate eagerly at startup — fail fast.
- No `.env` file loaders in production code.

## 11. Tracing initialization

```rust
use tracing_subscriber::EnvFilter;

pub fn init_tracing() {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .with_target(true)
        .json()
        .init();
}
```

Annotate service methods:

```rust
#[tracing::instrument(skip(self, request), err)]
async fn my_rpc(&self, request: Request<MyRequest>) -> Result<Response<MyResponse>, Status> {
    // ...
}
```

## 12. Testing

### Unit tests — call trait methods directly

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use tonic::Request;

    #[tokio::test]
    async fn returns_greeting() {
        let svc = MyServiceImpl::default();
        let req = Request::new(HelloRequest { name: "world".into() });
        let resp = svc.hello(req).await.unwrap();
        assert_eq!(resp.into_inner().message, "Hello, world!");
    }

    #[tokio::test]
    async fn rejects_empty_name() {
        let svc = MyServiceImpl::default();
        let req = Request::new(HelloRequest { name: String::new() });
        let status = svc.hello(req).await.unwrap_err();
        assert_eq!(status.code(), tonic::Code::InvalidArgument);
    }
}
```

### Interceptor tests

```rust
#[test]
fn auth_rejects_missing_token() {
    let req = Request::new(());
    let err = auth_interceptor(req).unwrap_err();
    assert_eq!(err.code(), tonic::Code::Unauthenticated);
}

#[test]
fn auth_accepts_valid_token() {
    let mut req = Request::new(());
    req.metadata_mut()
        .insert("x-auth-token", "secret".parse().unwrap());
    assert!(auth_interceptor(req).is_ok());
}
```

### Integration tests — real transport on random port

```rust
use tokio::net::TcpListener;
use tokio_stream::wrappers::TcpListenerStream;
use tonic::transport::{Channel, Server};

async fn spawn_server() -> String {
    let listener = TcpListener::bind("[::1]:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();

    tokio::spawn(async move {
        Server::builder()
            .add_service(MyServiceServer::new(MyServiceImpl::default()))
            .serve_with_incoming(TcpListenerStream::new(listener))
            .await
            .unwrap();
    });

    tokio::time::sleep(std::time::Duration::from_millis(50)).await;
    format!("http://[::1]:{port}")
}

#[tokio::test]
async fn integration_unary_call() {
    let addr = spawn_server().await;
    let mut client = MyServiceClient::connect(addr).await.unwrap();

    let mut req = Request::new(HelloRequest { name: "test".into() });
    req.metadata_mut()
        .insert("x-auth-token", "secret".parse().unwrap());

    let resp = client.hello(req).await.unwrap();
    assert_eq!(resp.into_inner().message, "Hello, test!");
}
```

## 13. Code quality checklist

### Error handling
- No `unwrap()` in non-test code. Use `?` with `.context()` or map to `Status`.
- Never leak internal details in `Status` messages.
- `#[tracing::instrument(skip(self, request), err)]` on every RPC method.
- Distinct error messages for "missing" vs "invalid" in interceptors.

### Interceptors
- Never log secrets.
- Use `LazyLock` for env-based config (not `lazy_static!`).
- Compose interceptors in a single function.

### Streaming
- Bounded channels only. Never use `mpsc::unbounded_channel`.
- Check `tx.send()` result. Break on `Err`.
- Spawn producer tasks.

### Concurrency and async
- No Arc with Mutex held across `.await`. Use `tokio::sync::Mutex` if needed.
- No blocking I/O in async context.
- Graceful shutdown always wired.

### Health and Kubernetes
- Always register `tonic-health` service.
- Monitor state transitions. Flip to `NOT_SERVING` when dependencies are unhealthy.
- Bind to `[::]:port` for container compatibility.

### Proto hygiene
- Suppress clippy pedantic on generated code.
- One proto package per service.
- Version proto packages (`my.service.v1`).

### State
- Arc with AppState for shared state. Store on the service struct.
- Prefer atomics for health flags and counters.

### Testing
- Unit tests call trait methods directly.
- Integration tests bind to port 0.
- Test both success and error paths.
- Test interceptors in isolation.

## Cargo.toml essentials

```toml
[dependencies]
tonic = "0.14"
tonic-health = "0.14"
prost = "0.14"
tokio = { version = "1", features = ["full"] }
tokio-stream = "0.1"
tokio-util = "0.7"
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter", "json"] }
serde = { version = "1", features = ["derive"] }
thiserror = "2"
anyhow = "1"
uuid = { version = "1", features = ["v7"] }

[build-dependencies]
tonic-prost-build = "0.14"

[dev-dependencies]
tokio-test = "0.4"
```
