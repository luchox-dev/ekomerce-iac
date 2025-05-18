# Meilisearch Docker Service

This Docker service provides a containerized setup for running Meilisearch, a powerful, fast, and open-source search engine designed to deliver relevant and typo-tolerant search results.

## Overview

The Meilisearch Docker service offers:

1. A lightweight, production-ready Meilisearch instance
2. Configurable environment variables for customization
3. Persistent data storage options
4. Proper security configurations with a dedicated non-root user

## Docker Image Details

- **Base Image**: Ubuntu 24.04
- **Exposed Port**: 7700
- **Default User**: meilisearch (non-root)
- **Data Directory**: /var/lib/meilisearch
- **Installed Packages**: curl, systemd

## Building the Image

```bash
# From the repository root
docker build -t meilisearch-service -f docker/Dockerfile.meilisearch .
```

## Running the Container

### Basic Usage

```bash
docker run -d --name meilisearch \
  -p 7700:7700 \
  meilisearch-service
```

### With Custom Master Key

```bash
docker run -d --name meilisearch \
  -p 7700:7700 \
  -e MEILISEARCH_MASTER_KEY=your_custom_key \
  meilisearch-service
```

### With Persistent Storage

```bash
docker run -d --name meilisearch \
  -p 7700:7700 \
  -e MEILISEARCH_MASTER_KEY=your_custom_key \
  -v meilisearch_data:/var/lib/meilisearch \
  meilisearch-service
```

## Environment Variables

You can customize your Meilisearch instance by setting these environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `MEILISEARCH_HTTP_ADDR` | 0.0.0.0:7700 | Address and port Meilisearch will listen on |
| `MEILISEARCH_MASTER_KEY` | masterKey | Authentication key (change for production) |
| `MEILISEARCH_ENV` | development | Environment (development or production) |
| `MEILISEARCH_NO_ANALYTICS` | true | Whether to disable sending analytics |

## Verifying Meilisearch is Running

```bash
# Check the health endpoint
curl -X GET "http://localhost:7700/health" -H "Authorization: Bearer your_master_key"
```

You should see a response like `{"status":"available"}` if Meilisearch is running correctly.

## Common Operations

### Viewing Logs

```bash
docker logs meilisearch
```

### Stopping the Container

```bash
docker stop meilisearch
```

### Restarting the Container

```bash
docker start meilisearch
```

## Node.js Integration Example

```javascript
// meilisearch-example.js
const { MeiliSearch } = require('meilisearch');

// Initialize the Meilisearch client
const client = new MeiliSearch({
  host: 'http://localhost:7700',
  apiKey: 'your_master_key', // Use the master key you set when running the container
});

async function main() {
  try {
    // Create an index if it doesn't exist
    const index = await client.getOrCreateIndex('products');
    
    // Add documents to the index
    const documents = [
      { id: 1, name: 'iPhone 13', price: 999, category: 'Smartphones' },
      { id: 2, name: 'Samsung Galaxy S21', price: 799, category: 'Smartphones' },
    ];
    
    const addedDocuments = await index.addDocuments(documents);
    console.log('Documents added:', addedDocuments);
    
    // Search for documents
    const search = await index.search('iphone');
    console.log('Search results:', search.hits);
    
  } catch (error) {
    console.error('Error:', error);
  }
}

main();
```

## Performance Considerations

For optimal performance, especially on smaller machines:

- The config limits indexing memory to 1 GiB with `max_indexing_memory = "1 GiB"`
- Limit the number of searchable attributes for large datasets
- Consider the document count - smaller instances handle ~100k docs efficiently

## Production Configuration

For production environments:

- **Always** change the master key
- Consider using HTTPS via a reverse proxy
- Set `MEILISEARCH_ENV=production`
- Create specific API keys instead of using the master key for clients

## AWS Deployment

For deploying to AWS EC2, see our comprehensive guide:
- [Deploy Meilisearch on AWS EC2](../deploy_meilisearch_on_aws_ec2.md)

## See Also

- [Meilisearch Documentation](https://docs.meilisearch.com/)
- [Meilisearch JavaScript Client](https://github.com/meilisearch/meilisearch-js)