package main

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

func TestScanProc(t *testing.T) {
	// Create a temporary directory for /proc
	tmpDir, err := os.MkdirTemp("", "proc_test")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	// Create some dummy processes
	procs := []struct {
		pid     int
		comm    string
		state   string
		ppid    int
		content string
	}{
		{
			pid:     1,
			comm:    "init",
			state:   "S",
			ppid:    0,
			content: "1 (init) S 0 1 1 0 -1 ...",
		},
		{
			pid:     100,
			comm:    "aush",
			state:   "R",
			ppid:    1,
			content: "100 (aush) R 1 100 100 0 -1 ...",
		},
		{
			pid:     200,
			comm:    "my shell",
			state:   "S",
			ppid:    100,
			content: "200 (my shell) S 100 200 200 0 -1 ...",
		},
	}

	for _, p := range procs {
		pidDir := filepath.Join(tmpDir, fmt.Sprintf("%d", p.pid))
		if err := os.Mkdir(pidDir, 0755); err != nil {
			t.Fatalf("Failed to create pid dir %s: %v", pidDir, err)
		}

		statFile := filepath.Join(pidDir, "stat")
		if err := os.WriteFile(statFile, []byte(p.content), 0644); err != nil {
			t.Fatalf("Failed to write stat file %s: %v", statFile, err)
		}
	}

	// Create a non-pid directory (should be ignored)
	if err := os.Mkdir(filepath.Join(tmpDir, "sys"), 0755); err != nil {
		t.Fatalf("Failed to create sys dir: %v", err)
	}

	// Run scanProc
	processes, err := scanProc(tmpDir)
	if err != nil {
		t.Fatalf("scanProc failed: %v", err)
	}

	// Verify results
	if len(processes) != len(procs) {
		t.Errorf("Expected %d processes, got %d", len(procs), len(processes))
	}

	procMap := make(map[int]Process)
	for _, p := range processes {
		procMap[p.PID] = p
	}

	for _, expected := range procs {
		got, ok := procMap[expected.pid]
		if !ok {
			t.Errorf("Process PID %d not found", expected.pid)
			continue
		}

		if got.Command != expected.comm {
			t.Errorf("PID %d: Expected command %q, got %q", expected.pid, expected.comm, got.Command)
		}
		if got.State != expected.state {
			t.Errorf("PID %d: Expected state %q, got %q", expected.pid, expected.state, got.State)
		}
		if got.PPID != expected.ppid {
			t.Errorf("PID %d: Expected PPID %d, got %d", expected.pid, expected.ppid, got.PPID)
		}
	}
}
