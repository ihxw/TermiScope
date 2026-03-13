# Production Deployment Guide

This guide provides instructions for deploying TermiScope in a production environment.

## 1. Docker Deployment (Recommended)

TermiScope is designed to be easily deployed using Docker.

### Steps:
1. Clone the repository to your server.
2. Edit `docker-compose.yml` if you need to change the port or volume mapping.
3. Run `docker-compose up -d`.

## 2. Reverse Proxy (Nginx)

For production, it is highly recommended to use a reverse proxy like Nginx for HTTPS termination and WebSocket stability.

### Example Nginx Configuration:

```nginx
server {
    listen 80;
    server_name your-ssh-domain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl;
    server_name your-ssh-domain.com;

    ssl_certificate /path/to/fullchain.pem;
    ssl_certificate_key /path/to/privkey.pem;

    location / {
        proxy_pass http://localhost:9287;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeout settings for long-lived SSH sessions
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
```

## 3. Security Best Practices

1. **Change Default Password**: Change the `admin` password immediately after first login.
2. **JWT Secret**: Set a strong `TermiScope_JWT_SECRET` in your environment variables.
3. **Encryption Key**: Use a persistent `TermiScope_ENCRYPTION_KEY` to ensure you can decrypt host information across restarts.
4. **Firewall**: Ensure port `9287` (or your chosen port) is protected and only accessible via your reverse proxy.

## 4. Troubleshooting

- **WebSocket Disconnection**: If sessions disconnect frequently, check your reverse proxy's `proxy_read_timeout` and `proxy_send_timeout` settings.
- **Database is Locked**: The app uses SQLite with WAL mode by default, which should handle concurrent access well. If you encounter locking issues, ensure the data volume has proper permissions.
