# OpenFGA Docker Deployment

This directory contains the Docker Compose configuration for running OpenFGA locally with PostgreSQL.

## Services

- **PostgreSQL**: Database backend for OpenFGA (port 5432)
- **OpenFGA**: Authorization server with HTTP, gRPC APIs, and Playground UI

## Ports

- `8080`: OpenFGA HTTP API
- `8081`: OpenFGA gRPC API
- `3000`: OpenFGA Playground UI (interactive web interface)
- `5432`: PostgreSQL database

## Quick Start

```bash
# Start services
docker-compose up -d

# View logs
docker-compose logs -f

# View OpenFGA logs only
docker-compose logs -f openfga

# Stop services
docker-compose down

# Stop and remove volumes (clean slate)
docker-compose down -v
```

## Accessing OpenFGA

### HTTP API
```bash
curl http://localhost:8080/healthz
```

### Playground UI
Open your browser to: http://localhost:3000

### FGA CLI Configuration
```bash
# Configure FGA CLI to use this server
fga store create --api-url http://localhost:8080
```

## Database Credentials

- **User**: openfga
- **Password**: openfga
- **Database**: openfga

## Health Checks

The configuration includes health checks for both services:
- PostgreSQL: Checks database readiness
- OpenFGA: Waits for PostgreSQL before starting

## Troubleshooting

### OpenFGA won't start
Check PostgreSQL logs:
```bash
docker-compose logs postgres
```

### Reset database
```bash
docker-compose down -v
docker-compose up -d
```

### Connect to PostgreSQL directly
```bash
docker exec -it fgabattle-postgres psql -U openfga -d openfga
```
