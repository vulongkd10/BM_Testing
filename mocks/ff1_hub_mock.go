package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"

	"github.com/gorilla/websocket"
)

// FF1 Hub & Player Mock Server for Suite 3 Standalone Testing
// Simulates feral-controld WebSocket commandrouter (port 1111) and emits L1, L2, L3 logs.

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

type CommandPayload struct {
	Command     string `json:"command"`
	PlaylistURL string `json:"playlist_url,omitempty"`
	PlaylistID  string `json:"playlist_id,omitempty"`
}

type LogEvent struct {
	Level       string `json:"level"`
	Msg         string `json:"msg"`
	PlaylistURL string `json:"playlist_url,omitempty"`
	PlaylistID  string `json:"playlist_id,omitempty"`
	Ok          bool   `json:"ok,omitempty"`
	From        string `json:"from,omitempty"`
	To          string `json:"to,omitempty"`
	Timestamp   string `json:"timestamp,omitempty"`
}

type ServerState struct {
	mu              sync.Mutex
	currentPlaylist string
	currentID       string
	logs            []LogEvent
}

var state = &ServerState{
	currentPlaylist: "https://feed.feralfile.com/api/v1/playlists/default-reset-000",
	currentID:       "default-reset-000",
}

func main() {
	port := os.Getenv("MOCK_PORT")
	if port == "" {
		port = "1111"
	}

	http.HandleFunc("/", handleWS)
	http.HandleFunc("/logs", handleLogs)
	http.HandleFunc("/cdp/screenshot", handleScreenshot)
	http.HandleFunc("/metrics", handleMetrics)

	server := &http.Server{Addr: ":" + port}

	log.Printf("[FF1 MOCK HUB] Starting WebSocket & Control Hub Mock on ws://127.0.0.1:%s", port)

	go func() {
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("[FF1 MOCK HUB] Listen error: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop

	log.Println("[FF1 MOCK HUB] Shutting down mock server cleanly...")
}

func handleWS(w http.ResponseWriter, r *http.Request) {
	if !websocket.IsWebSocketUpgrade(r) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprintln(w, "FF1 Hub Mock Server active. Connect via WebSocket.")
		return
	}

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("[FF1 MOCK HUB] Upgrade error: %v", err)
		return
	}
	defer conn.Close()

	log.Println("[FF1 MOCK HUB] Client connected to WebSocket hub.")

	for {
		_, message, err := conn.ReadMessage()
		if err != nil {
			log.Printf("[FF1 MOCK HUB] Read error / client disconnected: %v", err)
			break
		}

		log.Printf("[FF1 MOCK HUB] Received raw WS message: %s", string(message))

		var cmd CommandPayload
		if err := json.Unmarshal(message, &cmd); err != nil {
			msgStr := string(message)
			if strings.Contains(msgStr, "CMD_DISPLAY_DEFAULT_PLAYLIST") {
				cmd.Command = "CMD_DISPLAY_DEFAULT_PLAYLIST"
				cmd.PlaylistURL = "https://feed.feralfile.com/api/v1/playlists/default-reset-000"
				cmd.PlaylistID = "default-reset-000"
			} else if strings.Contains(msgStr, "http") {
				cmd.Command = "CMD_DISPLAY_PLAYLIST"
				cmd.PlaylistURL = msgStr
				parts := strings.Split(msgStr, "/")
				cmd.PlaylistID = parts[len(parts)-1]
			}
		}

		processCommand(conn, cmd)
	}
}

func processCommand(conn *websocket.Conn, cmd CommandPayload) {
	state.mu.Lock()
	defer state.mu.Unlock()

	targetURL := cmd.PlaylistURL
	if targetURL == "" && cmd.Command == "CMD_DISPLAY_DEFAULT_PLAYLIST" {
		targetURL = "https://feed.feralfile.com/api/v1/playlists/default-reset-000"
	}

	targetID := cmd.PlaylistID
	if targetID == "" {
		parts := strings.Split(targetURL, "/")
		targetID = parts[len(parts)-1]
	}

	// 1. Emit L1: Display playlist command received
	l1 := LogEvent{
		Level:       "INFO",
		Msg:         "Display playlist command received",
		PlaylistURL: targetURL,
	}
	state.logs = append(state.logs, l1)
	log.Printf("[LOG L1] msg=%q playlist_url=%q", l1.Msg, l1.PlaylistURL)
	conn.WriteJSON(l1)

	// 2. Emit L2: Playback verified
	l2 := LogEvent{
		Level:      "INFO",
		Msg:        "Playback verified",
		PlaylistID: targetID,
		Ok:         true,
	}
	state.logs = append(state.logs, l2)
	log.Printf("[LOG L2] msg=%q playlist_id=%q ok=%v", l2.Msg, l2.PlaylistID, l2.Ok)
	conn.WriteJSON(l2)

	// 3. Emit L3: Playlist switched
	oldURL := state.currentPlaylist
	state.currentPlaylist = targetURL
	state.currentID = targetID

	l3 := LogEvent{
		Level: "INFO",
		Msg:   "Playlist switched",
		From:  oldURL,
		To:    targetURL,
	}
	state.logs = append(state.logs, l3)
	log.Printf("[LOG L3] msg=%q from=%q to=%q", l3.Msg, l3.From, l3.To)
	conn.WriteJSON(l3)
}

func handleLogs(w http.ResponseWriter, r *http.Request) {
	state.mu.Lock()
	defer state.mu.Unlock()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(state.logs)
}

func handleScreenshot(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "image/png")
	png1x1 := []byte{
		0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
		0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
		0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
		0x0a, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
		0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49,
		0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
	}
	w.Write(png1x1)
}

func handleMetrics(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain")
	fmt.Fprintln(w, "# HELP playback_start_failures_total Total failed starts")
	fmt.Fprintln(w, "# TYPE playback_start_failures_total counter")
	fmt.Fprintln(w, "playback_start_failures_total 0")
	fmt.Fprintln(w, "# HELP art_playback_duration_seconds_total Total seconds played")
	fmt.Fprintln(w, "# TYPE art_playback_duration_seconds_total counter")
	fmt.Fprintln(w, "art_playback_duration_seconds_total 120.0")
}
