# Containerized Meilisearch for Local Development

This repository contains a Docker setup for running Meilisearch in a containerized environment, making it easy to use for local development with Node.js applications.

## What is Meilisearch?

Meilisearch is a powerful, fast, open-source, and easy-to-use search engine. It provides a RESTful API and is designed to deliver relevant and typo-tolerant search results for your applications.

## Getting Started

### Prerequisites

- Docker installed on your machine
- Node.js (for the application using Meilisearch)

### Building the Docker Image

```bash
# Build the Meilisearch Docker image
docker build -t meilisearch-local -f Dockerfile.meilisearch .
```

### Running the Container

```bash
# Run the Meilisearch container
docker run -d --name meilisearch \
  -p 7700:7700 \
  -e MEILISEARCH_MASTER_KEY=masterKey \
  -v meilisearch_data:/var/lib/meilisearch \
  meilisearch-local
```

This command:
- Runs the container in detached mode (`-d`)
- Names it "meilisearch" (`--name meilisearch`)
- Maps port 7700 from the container to your local machine (`-p 7700:7700`)
- Sets a master key for authentication (`-e MEILISEARCH_MASTER_KEY=masterKey`)
- Creates a persistent volume for data (`-v meilisearch_data:/var/lib/meilisearch`)

### Verifying Meilisearch is Running

```bash
# Check if the container is running
docker ps | grep meilisearch

# Check Meilisearch health
curl -X GET "http://localhost:7700/health" -H "Authorization: Bearer masterKey"
```

You should see a response like `{"status":"available"}` if Meilisearch is running correctly.

## Using Meilisearch with Node.js

### Installing the Meilisearch Client

```bash
# Using npm
npm install meilisearch

# Using yarn
yarn add meilisearch

# Using pnpm
pnpm add meilisearch
```

### Basic Usage Example

Here's a simple example of how to use Meilisearch with Node.js:

```javascript
// meilisearch-example.js
const { MeiliSearch } = require('meilisearch');

// Initialize the Meilisearch client
const client = new MeiliSearch({
  host: 'http://localhost:7700',
  apiKey: 'masterKey', // Use the master key you set when running the container
});

async function main() {
  try {
    // Create an index if it doesn't exist
    const index = await client.getOrCreateIndex('products');
    
    // Add documents to the index
    const documents = [
      { id: 1, name: 'iPhone 13', price: 999, category: 'Smartphones' },
      { id: 2, name: 'Samsung Galaxy S21', price: 799, category: 'Smartphones' },
      { id: 3, name: 'MacBook Pro', price: 1999, category: 'Laptops' },
      { id: 4, name: 'Dell XPS 15', price: 1499, category: 'Laptops' },
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

### Running the Example

```bash
node meilisearch-example.js
```

## Advanced Configuration

### Environment Variables

You can customize your Meilisearch instance by setting environment variables when running the container:

```bash
docker run -d --name meilisearch \
  -p 7700:7700 \
  -e MEILISEARCH_MASTER_KEY=your_custom_key \
  -e MEILISEARCH_ENV=production \
  -e MEILISEARCH_LOG_LEVEL=INFO \
  -v meilisearch_data:/var/lib/meilisearch \
  meilisearch-local
```

Common environment variables:
- `MEILISEARCH_MASTER_KEY`: Authentication key (required for security)
- `MEILISEARCH_ENV`: Environment (`development` or `production`)
- `MEILISEARCH_LOG_LEVEL`: Log level (`INFO`, `DEBUG`, `TRACE`, etc.)
- `MEILISEARCH_NO_ANALYTICS`: Set to `true` to disable sending analytics

### Persisting Data

To ensure your data persists between container restarts, always use a named volume:

```bash
docker volume create meilisearch_data

docker run -d --name meilisearch \
  -p 7700:7700 \
  -e MEILISEARCH_MASTER_KEY=masterKey \
  -v meilisearch_data:/var/lib/meilisearch \
  meilisearch-local
```

## Common Operations

### Stopping the Container

```bash
docker stop meilisearch
```

### Restarting the Container

```bash
docker start meilisearch
```

### Viewing Logs

```bash
docker logs meilisearch
```

### Removing the Container

```bash
docker rm -f meilisearch
```

## Resources

- [Meilisearch Documentation](https://docs.meilisearch.com/)
- [Meilisearch JavaScript Client](https://github.com/meilisearch/meilisearch-js)
- [Meilisearch GitHub Repository](https://github.com/meilisearch/meilisearch)