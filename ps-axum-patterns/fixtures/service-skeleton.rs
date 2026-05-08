// Axum service skeleton without health/ready endpoints
use axum::{
    routing::get,
    Router,
};
use std::sync::Arc;
use tokio::sync::RwLock;

#[derive(Clone)]
pub struct AppState {
    pub db_connection: Arc<RwLock<String>>,
}

pub async fn start_service(addr: &str) {
    let state = AppState {
        db_connection: Arc::new(RwLock::new("connected".to_string())),
    };

    let app = Router::new()
        .route("/api/status", get(status_handler))
        .with_state(state);

    // Server binding would go here
}

async fn status_handler() -> String {
    "Service running".to_string()
}
