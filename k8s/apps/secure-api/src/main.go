package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"
)

type HealthResponse struct {
	Status      string    `json:"status"`
	Service     string    `json:"service"`
	Environment string    `json:"environment"`
	Timestamp   time.Time `json:"timestamp"`
	ZeroTrust   bool      `json:"zero_trust"`
}

type MetricsResponse struct {
	UptimeSeconds float64 `json:"uptime_seconds"`
	SecurityModel string  `json:"security_model"`
	Isolation     string  `json:"isolation_level"`
	Encryption    string  `json:"encryption"`
}

var startTime time.Time

func main() {
	startTime = time.Now()
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", healthHandler)
	mux.HandleFunc("/api/v1/status", statusHandler)
	mux.HandleFunc("/api/v1/metrics", metricsHandler)

	server := &http.Server{
		Addr:         ":" + port,
		Handler:      mux,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	log.Printf("Starting Secure Microservice on port :%s", port)
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("Server failed to start: %v", err)
	}
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(HealthResponse{
		Status:      "healthy",
		Service:     "CloudDevSecOps-API",
		Environment: getEnv("ENVIRONMENT", "lab"),
		Timestamp:   time.Now().UTC(),
		ZeroTrust:   true,
	})
}

func statusHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"security_posture": "Restricted Pod Security Standard",
		"ebpf_cni":         "Cilium L7 Policy Enforced",
		"secrets_provider": "AWS Secrets Manager (IAM OIDC / Pod Identity)",
		"container_os":     "Distroless Non-Root (UID 65532)",
		"kms_envelope":     "Customer Managed Key (CMK)",
	})
}

func metricsHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(MetricsResponse{
		UptimeSeconds: time.Since(startTime).Seconds(),
		SecurityModel: "Zero Trust Defense-in-Depth",
		Isolation:     "eBPF Network Microsegmentation + IMDSv2 Hop Limit 1",
		Encryption:    "KMS CMK At-Rest + Strict TLS 1.3 In-Transit",
	})
}

func getEnv(key, fallback string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return fallback
}
