use crate::error::{AppRevealError, Result};
use crate::protocol::{handle_request, parse_json_rpc_request, JsonRpcResponse, RpcError};
use crate::registry::ToolRegistry;
use std::collections::HashMap;
use std::io::{BufRead, BufReader, Write};
use std::net::IpAddr;
use std::net::{SocketAddr, TcpListener, TcpStream};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread::{self, JoinHandle};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const DEFAULT_MAX_BODY_SIZE: usize = 1024 * 1024;
const MAX_HTTP_LINE_SIZE: usize = 16 * 1024;
const MAX_HTTP_HEADERS: usize = 100;
const SESSION_TOKEN_HEADER_NAME: &str = "x-appreveal-session";
const SESSION_TOKEN_QUERY_NAME: &str = "appreveal_session_token";

#[derive(Clone, Debug)]
pub struct ServerConfig {
    pub bind_addr: SocketAddr,
    pub read_timeout: Duration,
    pub accept_poll_interval: Duration,
    pub max_body_size: usize,
    pub session_token: Option<String>,
}

impl ServerConfig {
    pub fn localhost(port: u16) -> Self {
        Self {
            bind_addr: SocketAddr::from(([127, 0, 0, 1], port)),
            ..Self::default()
        }
    }

    pub fn any_interface(port: u16) -> Self {
        Self {
            bind_addr: SocketAddr::from(([0, 0, 0, 0], port)),
            ..Self::default()
        }
    }

    pub fn with_session_token(mut self, token: impl Into<String>) -> Self {
        self.session_token = Some(token.into());
        self
    }

    /// Disable auth only in crate tests. Normal builds keep the same
    /// session-token contract as the other AppReveal platforms.
    #[cfg(test)]
    pub fn without_session_token(mut self) -> Self {
        self.session_token = None;
        self
    }

    #[cfg(not(test))]
    pub fn without_session_token(self) -> Self {
        self
    }

    fn allows_browser_origins(&self) -> bool {
        self.bind_addr.ip().is_loopback()
    }
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            bind_addr: SocketAddr::from(([127, 0, 0, 1], 0)),
            read_timeout: Duration::from_secs(5),
            accept_poll_interval: Duration::from_millis(25),
            max_body_size: DEFAULT_MAX_BODY_SIZE,
            session_token: Some(create_session_token()),
        }
    }
}

pub fn start_server(config: ServerConfig, registry: ToolRegistry) -> Result<ServerHandle> {
    let listener = TcpListener::bind(config.bind_addr)?;
    listener.set_nonblocking(true)?;
    let local_addr = listener.local_addr()?;
    let shutdown = Arc::new(AtomicBool::new(false));
    let thread_shutdown = Arc::clone(&shutdown);
    let thread_config = config.clone();
    let session_token = config.session_token.clone();

    let thread = thread::spawn(move || {
        accept_loop(listener, registry, thread_shutdown, thread_config);
    });

    Ok(ServerHandle {
        local_addr,
        session_token,
        shutdown,
        thread: Some(thread),
    })
}

pub struct ServerHandle {
    local_addr: SocketAddr,
    session_token: Option<String>,
    shutdown: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
}

impl ServerHandle {
    pub fn local_addr(&self) -> SocketAddr {
        self.local_addr
    }

    pub fn port(&self) -> u16 {
        self.local_addr.port()
    }

    pub fn url(&self) -> String {
        format!("http://{}", self.local_addr)
    }

    pub fn session_token(&self) -> Option<&str> {
        self.session_token.as_deref()
    }

    pub fn session_url(&self) -> String {
        match self.session_token() {
            Some(token) => format!(
                "{}?{}={}",
                self.url(),
                SESSION_TOKEN_QUERY_NAME,
                url_encode_component(token)
            ),
            None => self.url(),
        }
    }

    pub fn stop(&mut self) -> Result<()> {
        self.shutdown.store(true, Ordering::SeqCst);
        if let Some(thread) = self.thread.take() {
            thread
                .join()
                .map_err(|_| AppRevealError::Protocol("server thread panicked".to_string()))?;
        }
        Ok(())
    }
}

impl Drop for ServerHandle {
    fn drop(&mut self) {
        let _ = self.stop();
    }
}

fn accept_loop(
    listener: TcpListener,
    registry: ToolRegistry,
    shutdown: Arc<AtomicBool>,
    config: ServerConfig,
) {
    while !shutdown.load(Ordering::SeqCst) {
        match listener.accept() {
            Ok((stream, _)) => {
                let registry = registry.clone();
                let connection_config = config.clone();
                thread::spawn(move || {
                    let _ = handle_connection(stream, registry, connection_config);
                });
            }
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                thread::sleep(config.accept_poll_interval);
            }
            Err(error) if error.kind() == std::io::ErrorKind::Interrupted => {}
            Err(_) => break,
        }
    }
}

fn handle_connection(
    mut stream: TcpStream,
    registry: ToolRegistry,
    config: ServerConfig,
) -> std::io::Result<()> {
    let request = match read_http_request(&mut stream, &config) {
        Ok(request) => request,
        Err(error) => {
            return write_json_response(
                &mut stream,
                error.status_code(),
                error.reason(),
                &JsonRpcResponse::error(None, RpcError::parse_error(error.to_string())),
                None,
            );
        }
    };

    let cors_origin = match cors_origin_policy(&config, &request.headers) {
        CorsOrigin::Absent => None,
        CorsOrigin::Allowed(origin) => Some(origin),
        CorsOrigin::Forbidden => {
            return write_text_response(
                &mut stream,
                403,
                "Forbidden",
                "Origin is not allowed",
                None,
            );
        }
    };
    let cors_origin = cors_origin.as_deref();

    if request.method == "OPTIONS" {
        return write_no_content(&mut stream, 204, "No Content", cors_origin);
    }

    if request.method == "GET" && path_without_query(&request.path) == "/health" {
        let body = serde_json::json!({
            "status": "ok",
            "port": stream.local_addr().map(|addr| addr.port()).unwrap_or(config.bind_addr.port()),
            "auth": if config.session_token.is_some() { "session-token" } else { "disabled" },
            "discovery": "manual"
        });
        return write_json_response(&mut stream, 200, "OK", &body, cors_origin);
    }

    if request.method != "POST" {
        return write_text_response(
            &mut stream,
            405,
            "Method Not Allowed",
            "Only POST is supported",
            cors_origin,
        );
    }

    if !is_authorized(&config, &request) {
        return write_json_response(
            &mut stream,
            401,
            "Unauthorized",
            &JsonRpcResponse::error(None, RpcError::internal_error("Unauthorized")),
            cors_origin,
        );
    }

    if request.body.is_empty() {
        return write_json_response(
            &mut stream,
            400,
            "Bad Request",
            &JsonRpcResponse::error(None, RpcError::parse_error("Empty body")),
            cors_origin,
        );
    }

    let rpc_request = match parse_json_rpc_request(&request.body) {
        Ok(request) => request,
        Err(response) => {
            return write_json_response(
                &mut stream,
                400,
                "Bad Request",
                response.as_ref(),
                cors_origin,
            );
        }
    };

    let expects_response = rpc_request.expects_response;
    let rpc_response = handle_request(&registry, rpc_request.request);
    if !expects_response {
        return write_no_content(&mut stream, 204, "No Content", cors_origin);
    }

    write_json_response(&mut stream, 200, "OK", &rpc_response, cors_origin)
}

struct HttpRequest {
    method: String,
    path: String,
    headers: HashMap<String, Vec<String>>,
    body: Vec<u8>,
}

enum CorsOrigin {
    Absent,
    Allowed(String),
    Forbidden,
}

#[derive(Debug)]
enum HttpReadError {
    BadRequest(String),
    PayloadTooLarge(String),
}

impl HttpReadError {
    fn status_code(&self) -> u16 {
        match self {
            Self::BadRequest(_) => 400,
            Self::PayloadTooLarge(_) => 413,
        }
    }

    fn reason(&self) -> &'static str {
        match self {
            Self::BadRequest(_) => "Bad Request",
            Self::PayloadTooLarge(_) => "Payload Too Large",
        }
    }
}

impl std::fmt::Display for HttpReadError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::BadRequest(detail) | Self::PayloadTooLarge(detail) => write!(f, "{detail}"),
        }
    }
}

impl From<std::io::Error> for HttpReadError {
    fn from(error: std::io::Error) -> Self {
        Self::BadRequest(error.to_string())
    }
}

fn read_http_request(
    stream: &mut TcpStream,
    config: &ServerConfig,
) -> std::result::Result<HttpRequest, HttpReadError> {
    stream.set_read_timeout(Some(config.read_timeout))?;
    let mut reader = BufReader::new(stream.try_clone()?);
    let request_line = read_required_http_line(&mut reader, "missing HTTP request line")?;
    let request_line = trim_http_line(&request_line);
    let mut request_parts = request_line.split_whitespace();
    let method = request_parts.next().unwrap_or_default().to_string();
    let path = request_parts.next().unwrap_or_default().to_string();
    let version = request_parts.next().unwrap_or_default();

    if method.is_empty()
        || path.is_empty()
        || !version.starts_with("HTTP/")
        || request_parts.next().is_some()
    {
        return Err(HttpReadError::BadRequest(
            "invalid HTTP request line".to_string(),
        ));
    }

    let headers = read_headers(&mut reader)?;
    let body = read_http_body(&mut reader, &headers, config.max_body_size)?;

    Ok(HttpRequest {
        method,
        path,
        headers,
        body,
    })
}

fn read_headers<R: BufRead>(
    reader: &mut R,
) -> std::result::Result<HashMap<String, Vec<String>>, HttpReadError> {
    let mut headers = HashMap::new();

    for _ in 0..MAX_HTTP_HEADERS {
        let line = read_required_http_line(reader, "headers not terminated")?;
        let line = trim_http_line(&line);
        if line.is_empty() {
            return Ok(headers);
        }

        let Some((name, value)) = line.split_once(':') else {
            return Err(HttpReadError::BadRequest(
                "malformed HTTP header".to_string(),
            ));
        };

        let name = name.trim().to_ascii_lowercase();
        if name.is_empty() {
            return Err(HttpReadError::BadRequest(
                "malformed HTTP header".to_string(),
            ));
        }

        headers
            .entry(name)
            .or_insert_with(Vec::new)
            .push(value.trim().to_string());
    }

    Err(HttpReadError::BadRequest(
        "too many HTTP headers".to_string(),
    ))
}

fn read_http_body<R: BufRead>(
    reader: &mut R,
    headers: &HashMap<String, Vec<String>>,
    max_body_size: usize,
) -> std::result::Result<Vec<u8>, HttpReadError> {
    if uses_chunked_transfer(headers)? {
        if headers.contains_key("content-length") {
            return Err(HttpReadError::BadRequest(
                "content-length is not allowed with chunked transfer encoding".to_string(),
            ));
        }

        return read_chunked_body(reader, max_body_size);
    }

    let content_length = parse_content_length(headers, max_body_size)?;
    let mut body = vec![0; content_length];
    if content_length > 0 {
        reader.read_exact(&mut body)?;
    }
    Ok(body)
}

fn uses_chunked_transfer(
    headers: &HashMap<String, Vec<String>>,
) -> std::result::Result<bool, HttpReadError> {
    let encodings: Vec<String> = header_values(headers, "transfer-encoding")
        .flat_map(|value| value.split(','))
        .map(|value| value.trim().to_ascii_lowercase())
        .filter(|value| !value.is_empty())
        .collect();

    if encodings.is_empty() {
        return Ok(false);
    }

    if encodings.len() == 1 && encodings[0] == "chunked" {
        return Ok(true);
    }

    Err(HttpReadError::BadRequest(
        "unsupported transfer encoding".to_string(),
    ))
}

fn parse_content_length(
    headers: &HashMap<String, Vec<String>>,
    max_body_size: usize,
) -> std::result::Result<usize, HttpReadError> {
    let mut parsed = None;

    for value in header_values(headers, "content-length") {
        for part in value.split(',') {
            let part = part.trim();
            if part.is_empty() {
                return Err(HttpReadError::BadRequest(
                    "invalid content-length".to_string(),
                ));
            }

            let length = part
                .parse::<usize>()
                .map_err(|_| HttpReadError::BadRequest("invalid content-length".to_string()))?;

            if matches!(parsed, Some(previous) if previous != length) {
                return Err(HttpReadError::BadRequest(
                    "conflicting content-length headers".to_string(),
                ));
            }

            parsed = Some(length);
        }
    }

    let content_length = parsed.unwrap_or(0);
    if content_length > max_body_size {
        return Err(HttpReadError::PayloadTooLarge(format!(
            "request body exceeds {} bytes",
            max_body_size
        )));
    }

    Ok(content_length)
}

fn read_chunked_body<R: BufRead>(
    reader: &mut R,
    max_body_size: usize,
) -> std::result::Result<Vec<u8>, HttpReadError> {
    let mut body = Vec::new();

    loop {
        let size_line = read_required_http_line(reader, "missing chunk size")?;
        let size_text = trim_http_line(&size_line)
            .split(';')
            .next()
            .unwrap_or_default()
            .trim();
        if size_text.is_empty() {
            return Err(HttpReadError::BadRequest("invalid chunk size".to_string()));
        }

        let chunk_size = usize::from_str_radix(size_text, 16)
            .map_err(|_| HttpReadError::BadRequest("invalid chunk size".to_string()))?;

        if chunk_size == 0 {
            read_chunk_trailers(reader)?;
            return Ok(body);
        }

        let new_len = body
            .len()
            .checked_add(chunk_size)
            .ok_or_else(|| HttpReadError::PayloadTooLarge("request body too large".to_string()))?;
        if new_len > max_body_size {
            return Err(HttpReadError::PayloadTooLarge(format!(
                "request body exceeds {} bytes",
                max_body_size
            )));
        }

        let start = body.len();
        body.resize(new_len, 0);
        reader.read_exact(&mut body[start..])?;

        let mut chunk_end = [0; 2];
        reader.read_exact(&mut chunk_end)?;
        if chunk_end != [b'\r', b'\n'] {
            return Err(HttpReadError::BadRequest(
                "malformed chunk terminator".to_string(),
            ));
        }
    }
}

fn read_chunk_trailers<R: BufRead>(reader: &mut R) -> std::result::Result<(), HttpReadError> {
    for _ in 0..MAX_HTTP_HEADERS {
        let line = read_required_http_line(reader, "chunk trailers not terminated")?;
        let line = trim_http_line(&line);
        if line.is_empty() {
            return Ok(());
        }

        if !line.contains(':') {
            return Err(HttpReadError::BadRequest(
                "malformed chunk trailer".to_string(),
            ));
        }
    }

    Err(HttpReadError::BadRequest(
        "too many chunk trailers".to_string(),
    ))
}

fn header_values<'a>(
    headers: &'a HashMap<String, Vec<String>>,
    name: &str,
) -> impl Iterator<Item = &'a str> {
    headers
        .get(name)
        .into_iter()
        .flat_map(|values| values.iter().map(String::as_str))
}

fn cors_origin_policy(config: &ServerConfig, headers: &HashMap<String, Vec<String>>) -> CorsOrigin {
    let mut origins = header_values(headers, "origin").filter(|origin| !origin.is_empty());
    let Some(origin) = origins.next() else {
        return CorsOrigin::Absent;
    };

    if origins.next().is_some() {
        return CorsOrigin::Forbidden;
    }

    if config.allows_browser_origins() && is_loopback_origin(origin) {
        CorsOrigin::Allowed(origin.to_string())
    } else {
        CorsOrigin::Forbidden
    }
}

fn is_authorized(config: &ServerConfig, request: &HttpRequest) -> bool {
    let Some(expected) = config.session_token.as_deref() else {
        return true;
    };

    header_values(&request.headers, SESSION_TOKEN_HEADER_NAME)
        .any(|value| token_matches(expected, value))
        || header_values(&request.headers, "authorization")
            .filter_map(read_bearer_token)
            .any(|value| token_matches(expected, value))
        || query_value(&request.path, SESSION_TOKEN_QUERY_NAME)
            .as_deref()
            .is_some_and(|value| token_matches(expected, value))
}

fn read_bearer_token(value: &str) -> Option<&str> {
    let prefix = "bearer ";
    if value.len() <= prefix.len() || !value[..prefix.len()].eq_ignore_ascii_case(prefix) {
        return None;
    }

    Some(value[prefix.len()..].trim())
}

fn query_value(path: &str, name: &str) -> Option<String> {
    let (_, query) = path.split_once('?')?;
    for pair in query.split('&') {
        let (key, value) = pair.split_once('=').unwrap_or((pair, ""));
        if percent_decode_component(key).as_deref() == Some(name) {
            return percent_decode_component(value);
        }
    }

    None
}

fn token_matches(expected: &str, candidate: &str) -> bool {
    let expected = expected.as_bytes();
    let candidate = candidate.as_bytes();
    if expected.len() != candidate.len() {
        return false;
    }

    expected
        .iter()
        .zip(candidate)
        .fold(0u8, |diff, (left, right)| diff | (left ^ right))
        == 0
}

fn is_loopback_origin(origin: &str) -> bool {
    if origin.contains(['\r', '\n']) {
        return false;
    }

    let Some((scheme, authority)) = origin.split_once("://") else {
        return false;
    };

    if scheme.is_empty()
        || !scheme
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'+' | b'-' | b'.'))
    {
        return false;
    }

    if authority.is_empty() || authority.contains('/') || authority.contains('@') {
        return false;
    }

    let host = if let Some(rest) = authority.strip_prefix('[') {
        let Some((host, remainder)) = rest.split_once(']') else {
            return false;
        };
        if !remainder.is_empty() && !remainder.starts_with(':') {
            return false;
        }
        host
    } else {
        let Some(host) = authority.split(':').next() else {
            return false;
        };
        if host.is_empty() {
            return false;
        }
        host
    };

    let host = host.trim_end_matches('.').to_ascii_lowercase();
    if host == "localhost" || host.ends_with(".localhost") {
        return true;
    }

    host.parse::<IpAddr>()
        .map(|addr| addr.is_loopback())
        .unwrap_or(false)
}

fn create_session_token() -> String {
    let mut bytes = [0u8; 32];
    if getrandom::fill(&mut bytes).is_ok() {
        return hex_encode(&bytes);
    }

    let fallback = format!(
        "{}:{}:{:?}",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|duration| duration.as_nanos())
            .unwrap_or_default(),
        thread::current().id()
    );
    hex_encode(fallback.as_bytes())
}

fn hex_encode(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut encoded = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        encoded.push(HEX[(byte >> 4) as usize] as char);
        encoded.push(HEX[(byte & 0x0f) as usize] as char);
    }

    encoded
}

fn url_encode_component(value: &str) -> String {
    let mut encoded = String::new();
    for byte in value.bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'.' | b'_' | b'~') {
            encoded.push(byte as char);
        } else {
            encoded.push('%');
            encoded.push(hex_digit(byte >> 4));
            encoded.push(hex_digit(byte & 0x0f));
        }
    }

    encoded
}

fn percent_decode_component(value: &str) -> Option<String> {
    let mut decoded = Vec::with_capacity(value.len());
    let mut bytes = value.as_bytes().iter().copied();
    while let Some(byte) = bytes.next() {
        if byte != b'%' {
            decoded.push(byte);
            continue;
        }

        let high = decode_hex_digit(bytes.next()?)?;
        let low = decode_hex_digit(bytes.next()?)?;
        decoded.push((high << 4) | low);
    }

    String::from_utf8(decoded).ok()
}

fn hex_digit(value: u8) -> char {
    match value {
        0..=9 => (b'0' + value) as char,
        10..=15 => (b'A' + value - 10) as char,
        _ => unreachable!("hex digit out of range"),
    }
}

fn decode_hex_digit(value: u8) -> Option<u8> {
    match value {
        b'0'..=b'9' => Some(value - b'0'),
        b'a'..=b'f' => Some(value - b'a' + 10),
        b'A'..=b'F' => Some(value - b'A' + 10),
        _ => None,
    }
}

fn read_required_http_line<R: BufRead>(
    reader: &mut R,
    eof_message: &'static str,
) -> std::result::Result<String, HttpReadError> {
    let mut line = Vec::new();
    let bytes_read = reader.read_until(b'\n', &mut line)?;
    if bytes_read == 0 {
        return Err(HttpReadError::BadRequest(eof_message.to_string()));
    }

    if line.len() > MAX_HTTP_LINE_SIZE {
        return Err(HttpReadError::BadRequest("HTTP line too long".to_string()));
    }

    String::from_utf8(line)
        .map_err(|_| HttpReadError::BadRequest("HTTP line is not UTF-8".to_string()))
}

fn trim_http_line(line: &str) -> &str {
    line.trim_end_matches(['\r', '\n'])
}

fn write_json_response<T: serde::Serialize>(
    stream: &mut TcpStream,
    status_code: u16,
    reason: &str,
    body: &T,
    cors_origin: Option<&str>,
) -> std::io::Result<()> {
    let body = serde_json::to_string(body).map_err(std::io::Error::other)?;
    write_raw_json_response(stream, status_code, reason, &body, cors_origin)
}

fn write_raw_json_response(
    stream: &mut TcpStream,
    status_code: u16,
    reason: &str,
    body: &str,
    cors_origin: Option<&str>,
) -> std::io::Result<()> {
    write_response(
        stream,
        status_code,
        reason,
        "application/json",
        body.as_bytes(),
        cors_origin,
    )
}

fn write_text_response(
    stream: &mut TcpStream,
    status_code: u16,
    reason: &str,
    body: &str,
    cors_origin: Option<&str>,
) -> std::io::Result<()> {
    write_response(
        stream,
        status_code,
        reason,
        "text/plain; charset=utf-8",
        body.as_bytes(),
        cors_origin,
    )
}

fn write_no_content(
    stream: &mut TcpStream,
    status_code: u16,
    reason: &str,
    cors_origin: Option<&str>,
) -> std::io::Result<()> {
    write_response(
        stream,
        status_code,
        reason,
        "text/plain; charset=utf-8",
        &[],
        cors_origin,
    )
}

fn write_response(
    stream: &mut TcpStream,
    status_code: u16,
    reason: &str,
    content_type: &str,
    body: &[u8],
    cors_origin: Option<&str>,
) -> std::io::Result<()> {
    write!(
        stream,
        "HTTP/1.1 {status_code} {reason}\r\n\
         content-type: {content_type}\r\n\
         content-length: {}\r\n\
         connection: close\r\n",
        body.len()
    )?;
    if let Some(origin) = cors_origin {
        write!(
            stream,
            "access-control-allow-origin: {origin}\r\n\
             access-control-allow-methods: GET, POST, OPTIONS\r\n\
             access-control-allow-headers: authorization, content-type, x-appreveal-session\r\n\
             vary: origin\r\n"
        )?;
    }
    write!(stream, "\r\n")?;
    stream.write_all(body)?;
    stream.flush()
}

fn path_without_query(path: &str) -> &str {
    path.split_once('?').map(|(path, _)| path).unwrap_or(path)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::AppReveal;
    use serde_json::{json, Value};
    use std::io::Read;

    #[test]
    fn server_accepts_posted_tool_call() {
        let mut appreveal = AppReveal::new();
        appreveal.register_state_provider(|| json!({ "screen": "cart" }));
        let addr = appreveal.start(insecure_config()).unwrap();

        let response = post_json(
            addr,
            &json!({
                "jsonrpc": "2.0",
                "id": 7,
                "method": "tools/call",
                "params": {
                    "name": "get_state",
                    "arguments": {}
                }
            })
            .to_string(),
        );

        appreveal.stop().unwrap();
        assert!(response.starts_with("HTTP/1.1 200 OK"));
        let body = response.split("\r\n\r\n").nth(1).unwrap();
        let body: Value = serde_json::from_str(body).unwrap();
        let text = body["result"]["content"][0]["text"].as_str().unwrap();
        assert_eq!(
            serde_json::from_str::<Value>(text).unwrap(),
            json!({ "screen": "cart" })
        );
    }

    #[test]
    fn server_accepts_chunked_json_body() {
        let mut appreveal = AppReveal::new();
        let addr = appreveal.start(insecure_config()).unwrap();
        let body = json!({
            "jsonrpc": "2.0",
            "id": 8,
            "method": "ping"
        })
        .to_string();

        let response = post_chunked(addr, &body);

        appreveal.stop().unwrap();
        assert!(response.starts_with("HTTP/1.1 200 OK"));
        assert_eq!(response_json(&response)["result"], json!({}));
    }

    #[test]
    fn server_suppresses_response_for_notification() {
        let mut appreveal = AppReveal::new();
        let addr = appreveal.start(insecure_config()).unwrap();

        let response = post_json(
            addr,
            &json!({
                "jsonrpc": "2.0",
                "method": "ping"
            })
            .to_string(),
        );

        appreveal.stop().unwrap();
        assert!(response.starts_with("HTTP/1.1 204 No Content"));
        assert_eq!(response.split("\r\n\r\n").nth(1), Some(""));
    }

    #[test]
    fn server_uses_parse_error_for_invalid_json() {
        let mut appreveal = AppReveal::new();
        let addr = appreveal.start(insecure_config()).unwrap();

        let response = post_json(addr, "{");

        appreveal.stop().unwrap();
        assert!(response.starts_with("HTTP/1.1 400 Bad Request"));
        assert_eq!(response_json(&response)["error"]["code"], json!(-32700));
    }

    #[test]
    fn server_rejects_json_rpc_with_missing_required_fields() {
        let mut appreveal = AppReveal::new();
        let addr = appreveal.start(insecure_config()).unwrap();

        let response = post_json(
            addr,
            &json!({
                "jsonrpc": "2.0",
                "id": 11
            })
            .to_string(),
        );

        appreveal.stop().unwrap();
        assert!(response.starts_with("HTTP/1.1 400 Bad Request"));
        assert_eq!(response_json(&response)["error"]["code"], json!(-32600));
    }

    #[test]
    fn server_rejects_invalid_content_length() {
        let mut appreveal = AppReveal::new();
        let addr = appreveal.start(insecure_config()).unwrap();

        let response = send_raw(
            addr,
            &format!("POST / HTTP/1.1\r\nhost: {addr}\r\ncontent-length: nope\r\n\r\n{{}}"),
        );

        appreveal.stop().unwrap();
        assert!(response.starts_with("HTTP/1.1 400 Bad Request"));
        assert_eq!(response_json(&response)["error"]["code"], json!(-32700));
    }

    #[test]
    fn server_rejects_body_over_configured_limit() {
        let mut appreveal = AppReveal::new();
        let addr = appreveal
            .start(ServerConfig {
                max_body_size: 8,
                ..insecure_config()
            })
            .unwrap();

        let response = post_json(
            addr,
            &json!({
                "jsonrpc": "2.0",
                "id": 9,
                "method": "ping"
            })
            .to_string(),
        );

        appreveal.stop().unwrap();
        assert!(response.starts_with("HTTP/1.1 413 Payload Too Large"));
        assert_eq!(response_json(&response)["error"]["code"], json!(-32700));
    }

    #[test]
    fn any_interface_binding_does_not_emit_wildcard_cors() {
        let mut appreveal = AppReveal::new();
        let addr = appreveal
            .start(ServerConfig::any_interface(0).without_session_token())
            .unwrap();
        let connect_addr = SocketAddr::from(([127, 0, 0, 1], addr.port()));

        let response = post_json(
            connect_addr,
            &json!({
                "jsonrpc": "2.0",
                "id": 10,
                "method": "ping"
            })
            .to_string(),
        );

        appreveal.stop().unwrap();
        assert!(!response.contains("access-control-allow-origin: *"));
    }

    #[test]
    fn loopback_origin_is_reflected_without_wildcard_cors() {
        let mut appreveal = AppReveal::new();
        let addr = appreveal.start(insecure_config()).unwrap();

        let response = post_json_with_origin(
            addr,
            "http://localhost:5173",
            &json!({
                "jsonrpc": "2.0",
                "id": 12,
                "method": "ping"
            })
            .to_string(),
        );

        appreveal.stop().unwrap();
        assert!(response.starts_with("HTTP/1.1 200 OK"));
        assert!(response.contains("access-control-allow-origin: http://localhost:5173"));
        assert!(!response.contains("access-control-allow-origin: *"));
    }

    #[test]
    fn non_loopback_origin_is_rejected() {
        let mut appreveal = AppReveal::new();
        let addr = appreveal.start(insecure_config()).unwrap();

        let response = post_json_with_origin(
            addr,
            "https://example.com",
            &json!({
                "jsonrpc": "2.0",
                "id": 13,
                "method": "ping"
            })
            .to_string(),
        );

        appreveal.stop().unwrap();
        assert!(response.starts_with("HTTP/1.1 403 Forbidden"));
        assert!(!response.contains("access-control-allow-origin"));
    }

    #[test]
    fn default_server_requires_session_token() {
        let mut appreveal = AppReveal::new();
        let addr = appreveal
            .start(ServerConfig::default().with_session_token("test-token"))
            .unwrap();
        let body = json!({
            "jsonrpc": "2.0",
            "id": 14,
            "method": "ping"
        })
        .to_string();

        let rejected = post_json(addr, &body);
        let accepted_with_header = post_json_with_session(addr, "test-token", &body);
        let accepted_with_query =
            post_json_at_path(addr, "/?appreveal_session_token=test-token", &body);

        appreveal.stop().unwrap();
        assert!(rejected.starts_with("HTTP/1.1 401 Unauthorized"));
        assert!(accepted_with_header.starts_with("HTTP/1.1 200 OK"));
        assert!(accepted_with_query.starts_with("HTTP/1.1 200 OK"));
    }

    fn insecure_config() -> ServerConfig {
        ServerConfig::default().without_session_token()
    }

    fn post_json(addr: SocketAddr, body: &str) -> String {
        post_json_at_path(addr, "/", body)
    }

    fn post_json_at_path(addr: SocketAddr, path: &str, body: &str) -> String {
        send_raw(
            addr,
            &format!(
                "POST {path} HTTP/1.1\r\nhost: {addr}\r\ncontent-type: application/json\r\ncontent-length: {}\r\n\r\n{body}",
                body.len()
            ),
        )
    }

    fn post_json_with_session(addr: SocketAddr, token: &str, body: &str) -> String {
        send_raw(
            addr,
            &format!(
                "POST / HTTP/1.1\r\nhost: {addr}\r\nx-appreveal-session: {token}\r\ncontent-type: application/json\r\ncontent-length: {}\r\n\r\n{body}",
                body.len()
            ),
        )
    }

    fn post_json_with_origin(addr: SocketAddr, origin: &str, body: &str) -> String {
        send_raw(
            addr,
            &format!(
                "POST / HTTP/1.1\r\nhost: {addr}\r\norigin: {origin}\r\ncontent-type: application/json\r\ncontent-length: {}\r\n\r\n{body}",
                body.len()
            ),
        )
    }

    fn post_chunked(addr: SocketAddr, body: &str) -> String {
        let midpoint = body.len() / 2;
        let first = &body[..midpoint];
        let second = &body[midpoint..];
        send_raw(
            addr,
            &format!(
                "POST / HTTP/1.1\r\nhost: {addr}\r\ncontent-type: application/json\r\ntransfer-encoding: chunked\r\n\r\n{:X}\r\n{first}\r\n{:X}\r\n{second}\r\n0\r\n\r\n",
                first.len(),
                second.len()
            ),
        )
    }

    fn send_raw(addr: SocketAddr, request: &str) -> String {
        let mut stream = TcpStream::connect(addr).unwrap();
        stream.write_all(request.as_bytes()).unwrap();
        stream.shutdown(std::net::Shutdown::Write).unwrap();
        let mut response = String::new();
        stream.read_to_string(&mut response).unwrap();
        response
    }

    fn response_json(response: &str) -> Value {
        let body = response.split("\r\n\r\n").nth(1).unwrap();
        serde_json::from_str(body).unwrap()
    }
}
