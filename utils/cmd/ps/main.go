package ps

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"text/tabwriter"
)

// Process represents a running process
type Process struct {
	PID     int
	PPID    int
	Command string
	State   string
}

// scanProc scans the given proc directory for processes
func scanProc(root string) ([]Process, error) {
	files, err := os.ReadDir(root)
	if err != nil {
		return nil, err
	}

	var processes []Process

	for _, f := range files {
		// Only look at numeric directories (PIDs)
		pid, err := strconv.Atoi(f.Name())
		if err != nil {
			continue
		}

		// Read status file
		// We try 'stat' first as it's standard, but could fall back or use status if needed.
		// Linux 'stat' format: pid (comm) state ppid ...
		data, err := os.ReadFile(filepath.Join(root, f.Name(), "stat"))
		if err != nil {
			continue
		}

		// Parse stat file
		// The comm field is surrounded by parentheses and can contain spaces.
		// So we find the first '(' and last ')'.
		content := string(data)
		startComm := strings.Index(content, "(")
		endComm := strings.LastIndex(content, ")")

		if startComm == -1 || endComm == -1 || endComm < startComm {
			continue
		}

		comm := content[startComm+1 : endComm]
		rest := content[endComm+2:] // Skip ") "
		fields := strings.Fields(rest)

		if len(fields) < 2 {
			continue
		}

		state := fields[0]
		ppid, _ := strconv.Atoi(fields[1])

		processes = append(processes, Process{
			PID:     pid,
			PPID:    ppid,
			Command: comm,
			State:   state,
		})
	}

	return processes, nil
}

func Run(args []string) {
	processes, err := scanProc("/proc")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error scanning /proc: %v\n", err)
		os.Exit(1)
	}

	// Use tabwriter for nice alignment
	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(w, "PID\tPPID\tSTATE\tCMD")

	for _, p := range processes {
		fmt.Fprintf(w, "%d\t%d\t%s\t%s\n", p.PID, p.PPID, p.State, p.Command)
	}
	w.Flush()
}
