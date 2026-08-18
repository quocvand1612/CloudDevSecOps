# Build Stage
FROM golang:1.22-alpine AS builder

WORKDIR /app
COPY src/main.go .

# Compile static, stripped binary (zero runtime dependencies)
RUN CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -ldflags="-s -w" -o secure-api main.go

# Production Stage: Distroless Static (Non-root UID:GID 65532:65532)
FROM gcr.io/distroless/static-debian12:nonroot

WORKDIR /
COPY --from=builder /app/secure-api /secure-api

# Expose non-privileged port
EXPOSE 8080

USER nonroot:nonroot

ENTRYPOINT ["/secure-api"]
