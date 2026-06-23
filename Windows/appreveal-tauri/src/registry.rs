use crate::error::{AppRevealError, Result};
use serde::Serialize;
use serde_json::Value;
use std::collections::BTreeMap;
use std::sync::{Arc, RwLock};

pub type ToolResult = Result<Value>;
type ToolHandler = dyn Fn(Option<&Value>) -> ToolResult + Send + Sync + 'static;
type AvailabilityPredicate = dyn Fn() -> bool + Send + Sync + 'static;

#[derive(Clone)]
pub struct Tool {
    name: String,
    description: String,
    input_schema: Value,
    handler: Arc<ToolHandler>,
    available: Arc<AvailabilityPredicate>,
}

impl Tool {
    pub fn new<F>(
        name: impl Into<String>,
        description: impl Into<String>,
        input_schema: Value,
        handler: F,
    ) -> Self
    where
        F: Fn(Option<&Value>) -> ToolResult + Send + Sync + 'static,
    {
        Self {
            name: name.into(),
            description: description.into(),
            input_schema,
            handler: Arc::new(handler),
            available: Arc::new(|| true),
        }
    }

    pub fn available_when<F>(mut self, available: F) -> Self
    where
        F: Fn() -> bool + Send + Sync + 'static,
    {
        self.available = Arc::new(available);
        self
    }

    pub fn name(&self) -> &str {
        &self.name
    }

    pub fn description(&self) -> &str {
        &self.description
    }

    pub fn input_schema(&self) -> &Value {
        &self.input_schema
    }

    pub fn metadata(&self) -> ToolMetadata {
        ToolMetadata {
            name: self.name.clone(),
            description: self.description.clone(),
            input_schema: self.input_schema.clone(),
        }
    }

    pub fn call(&self, arguments: Option<&Value>) -> ToolResult {
        (self.handler)(arguments)
    }

    pub fn is_available(&self) -> bool {
        (self.available)()
    }
}

#[derive(Clone, Debug, Serialize, PartialEq)]
pub struct ToolMetadata {
    pub name: String,
    pub description: String,
    #[serde(rename = "inputSchema")]
    pub input_schema: Value,
}

#[derive(Clone, Default)]
pub struct ToolRegistry {
    tools: Arc<RwLock<BTreeMap<String, Tool>>>,
}

impl ToolRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn register(&self, tool: Tool) -> Result<()> {
        if tool.name.trim().is_empty() {
            return Err(AppRevealError::InvalidParams(
                "tool name cannot be empty".to_string(),
            ));
        }

        let mut tools = self
            .tools
            .write()
            .map_err(|_| AppRevealError::Protocol("tool registry poisoned".to_string()))?;
        tools.insert(tool.name.clone(), tool);
        Ok(())
    }

    pub fn tool(&self, name: &str) -> Result<Option<Tool>> {
        let tool = {
            let tools = self
                .tools
                .read()
                .map_err(|_| AppRevealError::Protocol("tool registry poisoned".to_string()))?;
            tools.get(name).cloned()
        };

        Ok(tool.filter(Tool::is_available))
    }

    pub fn list(&self) -> Result<Vec<ToolMetadata>> {
        let tools = {
            let tools = self
                .tools
                .read()
                .map_err(|_| AppRevealError::Protocol("tool registry poisoned".to_string()))?;
            tools.values().cloned().collect::<Vec<_>>()
        };

        Ok(tools
            .into_iter()
            .filter(Tool::is_available)
            .map(|tool| tool.metadata())
            .collect())
    }

    pub fn clear(&self) -> Result<()> {
        let mut tools = self
            .tools
            .write()
            .map_err(|_| AppRevealError::Protocol("tool registry poisoned".to_string()))?;
        tools.clear();
        Ok(())
    }

    pub fn len(&self) -> Result<usize> {
        let tools = self
            .tools
            .read()
            .map_err(|_| AppRevealError::Protocol("tool registry poisoned".to_string()))?;
        Ok(tools.len())
    }

    pub fn is_empty(&self) -> Result<bool> {
        self.len().map(|len| len == 0)
    }
}
