use std::error::Error;
use std::fmt::{Display, Formatter};

pub type Result<T> = std::result::Result<T, AppRevealError>;

#[derive(Debug)]
pub enum AppRevealError {
    AlreadyStarted,
    Io(std::io::Error),
    Json(serde_json::Error),
    InvalidParams(String),
    Protocol(String),
    ToolNotFound(String),
    Tool(String),
}

impl Display for AppRevealError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::AlreadyStarted => write!(f, "AppReveal server is already running"),
            Self::Io(error) => write!(f, "I/O error: {error}"),
            Self::Json(error) => write!(f, "JSON error: {error}"),
            Self::InvalidParams(detail) => write!(f, "Invalid params: {detail}"),
            Self::Protocol(detail) => write!(f, "Protocol error: {detail}"),
            Self::ToolNotFound(name) => write!(f, "Tool not found: {name}"),
            Self::Tool(detail) => write!(f, "{detail}"),
        }
    }
}

impl Error for AppRevealError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        match self {
            Self::Io(error) => Some(error),
            Self::Json(error) => Some(error),
            _ => None,
        }
    }
}

impl From<std::io::Error> for AppRevealError {
    fn from(value: std::io::Error) -> Self {
        Self::Io(value)
    }
}

impl From<serde_json::Error> for AppRevealError {
    fn from(value: serde_json::Error) -> Self {
        Self::Json(value)
    }
}
