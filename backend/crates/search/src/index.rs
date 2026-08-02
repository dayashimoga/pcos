use std::path::PathBuf;
use tantivy::collector::TopDocs;
use tantivy::query::QueryParser;
use tantivy::schema::*;
use tantivy::{doc, Index, IndexReader, IndexWriter, ReloadPolicy};
use tokio::sync::RwLock;
use uuid::Uuid;
use std::sync::Arc;

/// Tantivy-based search index for file metadata.
pub struct SearchIndex {
    index: Index,
    reader: IndexReader,
    writer: Arc<RwLock<IndexWriter>>,
    schema: Schema,
    // Field handles
    pub id_field: Field,
    pub user_id_field: Field,
    pub name_field: Field,
    pub content_field: Field,
    pub mime_type_field: Field,
    pub entry_type_field: Field,
}

impl SearchIndex {
    /// Create or open a search index at the given path.
    pub fn open(index_path: &str) -> Result<Self, tantivy::TantivyError> {
        let mut schema_builder = Schema::builder();

        let id_field = schema_builder.add_text_field("id", STRING | STORED);
        let user_id_field = schema_builder.add_text_field("user_id", STRING);
        let name_field = schema_builder.add_text_field("name", TEXT | STORED);
        let content_field = schema_builder.add_text_field("content", TEXT);
        let mime_type_field = schema_builder.add_text_field("mime_type", STRING | STORED);
        let entry_type_field = schema_builder.add_text_field("entry_type", STRING | STORED);

        let schema = schema_builder.build();

        let path = PathBuf::from(index_path);
        std::fs::create_dir_all(&path).ok();

        let index = if path.join("meta.json").exists() {
            Index::open_in_dir(&path)?
        } else {
            Index::create_in_dir(&path, schema.clone())?
        };

        let reader = index.reader_builder()
            .reload_policy(ReloadPolicy::OnCommitWithDelay)
            .try_into()?;

        let writer = index.writer(50_000_000)?; // 50MB heap

        Ok(Self {
            index,
            reader,
            writer: Arc::new(RwLock::new(writer)),
            schema,
            id_field,
            user_id_field,
            name_field,
            content_field,
            mime_type_field,
            entry_type_field,
        })
    }

    /// Index a file entry.
    pub async fn index_document(
        &self,
        id: Uuid,
        user_id: Uuid,
        name: &str,
        content: &str,
        mime_type: &str,
        entry_type: &str,
    ) -> Result<(), tantivy::TantivyError> {
        let mut writer = self.writer.write().await;

        // Delete existing document with same ID
        let id_term = tantivy::Term::from_field_text(self.id_field, &id.to_string());
        writer.delete_term(id_term);

        writer.add_document(doc!(
            self.id_field => id.to_string(),
            self.user_id_field => user_id.to_string(),
            self.name_field => name,
            self.content_field => content,
            self.mime_type_field => mime_type,
            self.entry_type_field => entry_type,
        ))?;

        writer.commit()?;
        Ok(())
    }

    /// Search for documents matching the query, filtered by user.
    pub fn search(
        &self,
        user_id: Uuid,
        query_str: &str,
        limit: usize,
    ) -> Result<Vec<SearchResult>, tantivy::TantivyError> {
        let searcher = self.reader.searcher();
        let query_parser = QueryParser::for_index(&self.index, vec![self.name_field, self.content_field]);

        // Combine user filter with search query
        let full_query = format!("user_id:{} AND ({})", user_id, query_str);
        let query = query_parser.parse_query(&full_query)
            .unwrap_or_else(|_| {
                // Fallback to just name search
                let simple = query_parser.parse_query(query_str).unwrap_or_else(|_| {
                    Box::new(tantivy::query::AllQuery)
                });
                simple
            });

        let top_docs = searcher.search(&query, &TopDocs::with_limit(limit))?;

        let mut results = Vec::new();
        for (_score, doc_address) in top_docs {
            let doc: tantivy::TantivyDocument = searcher.doc(doc_address)?;

            let id = doc.get_first(self.id_field)
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string();
            let name = doc.get_first(self.name_field)
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string();
            let mime = doc.get_first(self.mime_type_field)
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string();
            let etype = doc.get_first(self.entry_type_field)
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string();

            results.push(SearchResult {
                id,
                name,
                mime_type: mime,
                entry_type: etype,
                score: _score,
            });
        }

        Ok(results)
    }

    /// Remove a document from the index.
    pub async fn remove_document(&self, id: Uuid) -> Result<(), tantivy::TantivyError> {
        let mut writer = self.writer.write().await;
        let term = tantivy::Term::from_field_text(self.id_field, &id.to_string());
        writer.delete_term(term);
        writer.commit()?;
        Ok(())
    }
}

#[derive(Debug, serde::Serialize)]
pub struct SearchResult {
    pub id: String,
    pub name: String,
    pub mime_type: String,
    pub entry_type: String,
    pub score: f32,
}
