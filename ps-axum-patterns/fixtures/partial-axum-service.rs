// Partial Axum service - routes to be added
use axum::{
    routing::{get, post, delete},
    Router,
};
use std::sync::Arc;

#[derive(Clone)]
pub struct AppState {
    // Add shared state fields here
}

pub fn create_router(state: AppState) -> Router {
    Router::new()
        .route("/health", get(health_check))
        .with_state(state)
}

async fn health_check() -> &'static str {
    "OK"
}
