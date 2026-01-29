# Security Documentation

This document describes the security features implemented in the Debt Tracker application and how to configure them for production.

## Authentication

### JWT Authentication
- All API endpoints (except login and health check) require JWT authentication
- Tokens are issued with configurable expiration (default: 3600 seconds)
- Tokens are validated on every request
- Separate authentication for regular users and admin users

### Admin Authentication
- Admin panel uses separate `admin_users` table
- Admin credentials are managed separately from regular user accounts
- Use `./scripts/manage.sh set-admin-password <username> <password>` to change admin password

## Rate Limiting

Rate limiting is implemented to prevent abuse and DDoS attacks.

### Configuration
- **RATE_LIMIT_REQUESTS**: Maximum requests per window (default: 100)
- **RATE_LIMIT_WINDOW**: Time window in seconds (default: 60)

### Environment Variables
```bash
RATE_LIMIT_REQUESTS=100
RATE_LIMIT_WINDOW=60
```

### Behavior
- Rate limiting is applied globally to all routes
- Limits are tracked per IP address
- When limit is exceeded, returns `429 Too Many Requests`
- IP extraction supports reverse proxy headers (`X-Forwarded-For`, `X-Real-IP`)

## HTTPS/TLS Setup

### Development
For development, the server runs on HTTP by default. This is acceptable for local development.

### Production - Recommended: Reverse Proxy

**We strongly recommend using a reverse proxy (nginx, Caddy, Traefik) for HTTPS in production.**

#### Why Use a Reverse Proxy?
1. **Certificate Management**: Reverse proxies handle Let's Encrypt certificates automatically
2. **Performance**: Reverse proxies are optimized for SSL/TLS termination
3. **Flexibility**: Easy to add multiple services, load balancing, etc.
4. **Security**: Can add additional security headers, DDoS protection, etc.

#### Example: nginx Configuration

```nginx
server {
    listen 443 ssl http2;
    server_name your-domain.com;

    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    location / {
        proxy_pass http://localhost:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name your-domain.com;
    return 301 https://$server_name$request_uri;
}
```

#### Example: Caddy Configuration

```caddy
your-domain.com {
    reverse_proxy localhost:8000 {
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
```

Caddy automatically handles HTTPS with Let's Encrypt!

### Production - Direct TLS (Not Recommended)

If you must run TLS directly in the Rust server:

1. **Obtain Certificates**:
   ```bash
   # Using Let's Encrypt with certbot
   certbot certonly --standalone -d your-domain.com
   ```

2. **Set Environment Variables**:
   ```bash
   ENABLE_TLS=true
   TLS_CERT_PATH=/etc/letsencrypt/live/your-domain.com/fullchain.pem
   TLS_KEY_PATH=/etc/letsencrypt/live/your-domain.com/privkey.pem
   ```

3. **Start Server**:
   The server will automatically use HTTPS when `ENABLE_TLS=true` and certificates are provided.

**Note**: Certificate renewal must be handled manually. Reverse proxies handle this automatically.

## Security Headers

The following security headers are automatically added to all responses:

- `X-Content-Type-Options: nosniff` - Prevents MIME type sniffing
- `X-Frame-Options: DENY` - Prevents clickjacking
- `X-XSS-Protection: 1; mode=block` - Enables XSS protection
- `Content-Security-Policy` - Restricts resource loading
- `Referrer-Policy: strict-origin-when-cross-origin` - Controls referrer information
- `Permissions-Policy` - Restricts browser features

## CORS Configuration

CORS is configured to restrict which origins can access the API.

### Configuration
- **ALLOWED_ORIGINS**: Comma-separated list of allowed origins (default: `*` for development)

### Environment Variables
```bash
ALLOWED_ORIGINS=https://your-domain.com,https://app.your-domain.com
```

**Warning**: Never use `*` in production! Always specify exact origins.

## Mobile App HTTPS Support

The mobile app supports both HTTP and HTTPS connections.

### Configuration
The mobile app can be configured to use HTTPS through the backend configuration screen:
- Enable HTTPS in the backend settings
- The app will automatically use `https://` and `wss://` protocols

### Certificate Validation
- For production certificates (Let's Encrypt, etc.), the app will validate certificates automatically
- For self-signed certificates in development, you may need to configure certificate pinning or allow self-signed certificates (development only!)

## WebSocket Security

- WebSocket connections require JWT authentication
- Tokens are validated before establishing the connection
- Supports both `ws://` (HTTP) and `wss://` (HTTPS) protocols
- User isolation: users only receive their own real-time updates

## Login Logging

All login attempts (successful and failed) are logged with:
- User ID (if found)
- Timestamp
- IP address
- User agent
- Success/failure status
- Failure reason (if applicable)

Admins can view login logs through the admin panel.

## Password Security

- Passwords are hashed using bcrypt
- Minimum password length: 8 characters (enforced in admin panel)
- Passwords are never stored in plain text
- Password changes require authentication

## Best Practices

1. **Change Default Secrets**: Always change `JWT_SECRET` in production
2. **Use Strong Passwords**: Enforce strong password policies
3. **Enable HTTPS**: Always use HTTPS in production
4. **Restrict CORS**: Never use `*` for `ALLOWED_ORIGINS` in production
5. **Monitor Logs**: Regularly review login logs for suspicious activity
6. **Rate Limiting**: Adjust rate limits based on your traffic patterns
7. **Keep Dependencies Updated**: Regularly update dependencies for security patches
8. **Use Reverse Proxy**: Use a reverse proxy for production HTTPS setup

## Environment Variables Summary

```bash
# Authentication
JWT_SECRET=your-secret-key-change-in-production
JWT_EXPIRATION=3600

# Rate Limiting
RATE_LIMIT_REQUESTS=100
RATE_LIMIT_WINDOW=60

# CORS
ALLOWED_ORIGINS=https://your-domain.com

# TLS (if using direct TLS, not recommended)
ENABLE_TLS=false
TLS_CERT_PATH=/path/to/cert.pem
TLS_KEY_PATH=/path/to/key.pem

# Database
DATABASE_URL=postgresql://user:password@localhost:5432/dbname
```

## Security Checklist

- [ ] Changed `JWT_SECRET` from default value
- [ ] Configured `ALLOWED_ORIGINS` (not using `*`)
- [ ] Enabled HTTPS (via reverse proxy recommended)
- [ ] Configured rate limiting appropriately
- [ ] Set strong admin password
- [ ] Reviewed and updated security headers if needed
- [ ] Configured mobile app for HTTPS if using HTTPS
- [ ] Set up monitoring for suspicious login attempts
- [ ] Regularly update dependencies
- [ ] Back up database regularly
