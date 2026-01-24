# Stage 1: Build Frontend
FROM node:20-alpine AS frontend-builder
WORKDIR /web
COPY web/package*.json ./
RUN npm install
COPY web/ ./
RUN npm run build

# Stage 2: Build Backend
FROM golang:1.21-alpine AS backend-builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
# Copy built frontend assets to be embedded
COPY --from=frontend-builder /web/dist /app/web/dist
RUN CGO_ENABLED=0 GOOS=linux go build -o main ./cmd/server/main.go

# Stage 3: Final Image
FROM alpine:latest
RUN apk --no-cache add ca-certificates tzdata
WORKDIR /app
COPY --from=backend-builder /app/main .
COPY --from=backend-builder /app/configs/config.yaml ./configs/config.yaml
# Ensure data directory exists
RUN mkdir -p /app/data

EXPOSE 3000
CMD ["./main"]
