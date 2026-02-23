package ps

import (
	"os"
	"path/filepath"
	"strconv"
	"testing"
)

func TestScanProc(t *testing.T) {
	// Create a fake /proc
	tmpDir := t.TempDir()

	// Create process directories
	pids := []struct {
		pid   int
		ppid  int
		comm  string
		state string
	}{
		{1, 0, "init", "S"},
		{100, 1, "bash", "S"},
		{200, 100, "ls", "R"},
	}

	for _, p := range pids {
		pidDir := filepath.Join(tmpDir, strconv.Itoa(p.pid))
		if err := os.Mkdir(pidDir, 0755); err != nil {
			t.Fatal(err)
		}

		// Create stat file
		// pid (comm) state ppid ...
		content := strconv.Itoa(p.pid) + " (" + p.comm + ") " + p.state + " " + strconv.Itoa(p.ppid) + " 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0"
		if err := os.WriteFile(filepath.Join(pidDir, "stat"), []byte(content), 0644); err != nil {
			t.Fatal(err)
		}
	}

	// Create a non-pid directory (should be ignored)
	if err := os.Mkdir(filepath.Join(tmpDir, "sys"), 0755); err != nil {
		t.Fatal(err)
	}

	// Run scanProc
	procs, err := scanProc(tmpDir)
	if err != nil {
		t.Fatalf("scanProc failed: %v", err)
	}

	// Verify results
	if len(procs) != len(pids) {
		t.Errorf("expected %d processes, got %d", len(pids), len(procs))
	}

	for _, p := range pids {
		found := false
		for _, proc := range procs {
			if proc.PID == p.pid {
				found = true
				if proc.PPID != p.ppid {
					t.Errorf("PID %d: expected PPID %d, got %d", p.pid, p.ppid, proc.PPID)
				}
				if proc.Command != p.comm {
					t.Errorf("PID %d: expected Command %s, got %s", p.pid, p.comm, proc.Command)
				}
				if proc.State != p.state {
					t.Errorf("PID %d: expected State %s, got %s", p.pid, p.state, proc.State)
				}
				break
			}
		}
		if !found {
			t.Errorf("PID %d not found", p.pid)
		}
	}
}
