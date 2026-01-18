# Deployment Guide

## Development Setup

### Prerequisites
- Rust (latest stable)
- Flutter SDK
- Docker & Docker Compose
- PostgreSQL (via Docker)
- Redis (via Docker, optional)

### Backend Setup

1. **Start Docker services**
   ```bash
   cd backend
   docker-compose up -d
   ```

2. **Run migrations**
   ```bash
   cd rust-api
   cargo run --bin migrate
   ```

3. **Start server**
   ```bash
   cargo run
   ```

Server runs on `http://localhost:8000`

### Frontend Setup

1. **Install dependencies**
   ```bash
   cd mobile
   flutter pub get
   ```

2. **Run web app**
   ```bash
   flutter run -d web-server --web-port 8080
   ```

3. **Run desktop app**
   ```bash
   flutter run -d linux
   ```

4. **Build for production**
   ```bash
   # Web
   flutter build web --no-source-maps
   
   # Linux
   flutter build linux
   ```

## Production Deployment

### Backend

1. **Build release binary**
   ```bash
   cd backend/rust-api
   cargo build --release
   ```

2. **Run with systemd** (example)
   ```ini
   [Unit]
   Description=Debt Tracker API
   After=network.target

   [Service]
   Type=simple
   User=debt-tracker
   WorkingDirectory=/opt/debt-tracker/backend/rust-api
   ExecStart=/opt/debt-tracker/backend/rust-api/target/release/debt-tracker-api
   Restart=always

   [Install]
   WantedBy=multi-user.target
   ```

3. **Environment variables**
   ```bash
   DATABASE_URL=postgresql://user:pass@localhost/debt_tracker
   PORT=8000
   RUST_LOG=info
   ```

### Frontend

1. **Build web app**
   ```bash
   cd mobile
   flutter build web --release --no-source-maps
   ```

2. **Serve with nginx** (example)
   ```nginx
   server {
       listen 80;
       server_name your-domain.com;
       
       root /opt/debitum/mobile/build/web;
       index index.html;
       
       location / {
           try_files $uri $uri/ /index.html;
       }
   }
   ```

3. **WebSocket proxy** (for real-time)
   ```nginx
   location /ws {
       proxy_pass http://localhost:8000;
       proxy_http_version 1.1;
       proxy_set_header Upgrade $http_upgrade;
       proxy_set_header Connection "upgrade";
   }
   ```

## Docker Deployment

### Backend Dockerfile
```dockerfile
FROM rust:1.75 as builder
WORKDIR /app
COPY . .
RUN cargo build --release

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates
COPY --from=builder /app/target/release/debt-tracker-api /usr/local/bin/
CMD ["debt-tracker-api"]
```

### Docker Compose (Production)
```yaml
version: '3.8'
services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: debt_tracker
      POSTGRES_USER: debt_tracker
      POSTGRES_PASSWORD: secure_password
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  api:
    build: ./backend/rust-api
    environment:
      DATABASE_URL: postgresql://debt_tracker:secure_password@postgres/debt_tracker
      PORT: 8000
    ports:
      - "8000:8000"
    depends_on:
      - postgres

  web:
    image: nginx:alpine
    volumes:
      - ./mobile/build/web:/usr/share/nginx/html
    ports:
      - "80:80"
    depends_on:
      - api

volumes:
  postgres_data:
```

## Backup Strategy

### Database Backups
```bash
# Automated backup script (run via cron)
pg_dump -U debt_tracker debt_tracker > backup_$(date +%Y%m%d).sql
```

### Event Store Backup
Since events are immutable, backing up the events table ensures complete recovery:
```sql
COPY events TO '/backup/events_$(date +%Y%m%d).csv';
```

## Monitoring

### Health Checks
- Backend: `GET /health`
- Database: Connection pool status
- WebSocket: Connection count

### Logging
- Backend: Structured logging with `tracing`
- Frontend: Console logs (development), remote logging (production)

## Security Checklist

- [ ] Use HTTPS/WSS in production
- [ ] Set secure database passwords
- [ ] Enable authentication (JWT)
- [ ] Rate limiting
- [ ] CORS configuration
- [ ] Input validation
- [ ] SQL injection prevention (SQLx handles this)
- [ ] Encrypted backups
