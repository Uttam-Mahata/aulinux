package groupadd

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
	"syscall"
)

const groupFile = "/etc/group"

func Run(args []string) {
	// Check root privileges
	if os.Getuid() != 0 {
		fmt.Fprintln(os.Stderr, "Error: this command must be run as root")
		os.Exit(1)
	}

	if len(args) < 1 {
		fmt.Println("Usage: groupadd <groupname>")
		os.Exit(1)
	}

	groupname := args[0]

	// Open group file for read-write (create if not exists)
	f, err := os.OpenFile(groupFile, os.O_RDWR|os.O_CREATE, 0644)
	if err != nil {
		fmt.Printf("Error opening %s: %v\n", groupFile, err)
		os.Exit(1)
	}
	defer f.Close()

	// Acquire exclusive lock
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		fmt.Printf("Error locking %s: %v\n", groupFile, err)
		os.Exit(1)
	}
	defer syscall.Flock(int(f.Fd()), syscall.LOCK_UN)

	if groupExists(f, groupname) {
		fmt.Printf("Group '%s' already exists\n", groupname)
		os.Exit(1)
	}

	gid := getNextGID(f)

	// Format: groupname:x:GID:
	entry := fmt.Sprintf("%s:x:%d:\n", groupname, gid)

	// Seek to end of file before writing
	if _, err := f.Seek(0, 2); err != nil {
		fmt.Printf("Error seeking to end of %s: %v\n", groupFile, err)
		os.Exit(1)
	}

	if _, err := f.WriteString(entry); err != nil {
		fmt.Printf("Error writing to %s: %v\n", groupFile, err)
		os.Exit(1)
	}

	fmt.Printf("Group '%s' created with GID %d\n", groupname, gid)
}

func groupExists(f *os.File, name string) bool {
	if _, err := f.Seek(0, 0); err != nil {
		return false
	}

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		parts := strings.Split(scanner.Text(), ":")
		if len(parts) > 0 && parts[0] == name {
			return true
		}
	}
	return false
}

func getNextGID(f *os.File) int {
	if _, err := f.Seek(0, 0); err != nil {
		return 1000
	}

	maxGID := 999
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		parts := strings.Split(scanner.Text(), ":")
		if len(parts) > 2 {
			gid, err := strconv.Atoi(parts[2])
			if err == nil && gid > maxGID {
				maxGID = gid
			}
		}
	}
	return maxGID + 1
}

