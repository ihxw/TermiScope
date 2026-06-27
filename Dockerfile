# Stage 1: Build Frontend
FROM node:20-alpine AS frontend-builder
WORKDIR /web
COPY web/package*.json ./
RUN npm install
COPY web/ ./
RUN npm run build

# Stage 2: Build Backend & Agents
FROM golang:1.25-alpine AS backend-builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
# Copy built frontend assets to be embedded or served
COPY --from=frontend-builder /web/dist /app/web/dist
RUN CGO_ENABLED=0 GOOS=linux go build -o main ./cmd/server/main.go

# Build Agents
RUN mkdir -p /app/agents
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /app/agents/termiscope-agent-linux-amd64 ./cmd/agent
RUN CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o /app/agents/termiscope-agent-linux-arm64 ./cmd/agent
RUN CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=7 go build -o /app/agents/termiscope-agent-linux-arm ./cmd/agent
RUN CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -o /app/agents/termiscope-agent-windows-amd64.exe ./cmd/agent
RUN CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build -o /app/agents/termiscope-agent-darwin-amd64 ./cmd/agent
RUN CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -o /app/agents/termiscope-agent-darwin-arm64 ./cmd/agent

# Stage 3: Final Image
FROM alpine:3.21
RUN apk --no-cache add ca-certificates tzdata
WORKDIR /app
COPY --from=backend-builder /app/main .
COPY --from=backend-builder /app/configs/config.example.yaml ./configs/config.example.yaml
COPY --from=backend-builder /app/agents ./agents
COPY --from=frontend-builder /web/dist ./web/dist
# Ensure data directory exists
RUN mkdir -p /app/data

EXPOSE 3000
CMD ["./main"]
