package useradd

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
	"syscall"
)

const passwdFile = "/etc/passwd"

func Run(args []string) {
	// Check root privileges
	if os.Getuid() != 0 {
		fmt.Fprintln(os.Stderr, "Error: this command must be run as root")
		os.Exit(1)
	}

	if len(args) < 1 {
		fmt.Println("Usage: useradd <username>")
		os.Exit(1)
	}

	username := args[0]

	// Open passwd file for read-write (create if not exists)
	f, err := os.OpenFile(passwdFile, os.O_RDWR|os.O_CREATE, 0644)
	if err != nil {
		fmt.Printf("Error opening %s: %v\n", passwdFile, err)
		os.Exit(1)
	}
	defer f.Close()

	// Acquire exclusive lock
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		fmt.Printf("Error locking %s: %v\n", passwdFile, err)
		os.Exit(1)
	}
	defer syscall.Flock(int(f.Fd()), syscall.LOCK_UN)

	// Check if user exists
	if userExists(f, username) {
		fmt.Printf("User '%s' already exists\n", username)
		os.Exit(1)
	}

	// Find next UID
	uid, gid := getNextUID(f)

	// Append to /etc/passwd
	// Format: username:x:UID:GID:gecos:home:shell
	entry := fmt.Sprintf("%s:x:%d:%d:%s:/home/%s:/bin/aush\n", username, uid, gid, username, username)

	// Seek to end of file before writing
	if _, err := f.Seek(0, 2); err != nil {
		fmt.Printf("Error seeking to end of %s: %v\n", passwdFile, err)
		os.Exit(1)
	}

	if _, err := f.WriteString(entry); err != nil {
		fmt.Printf("Error writing to %s: %v\n", passwdFile, err)
		os.Exit(1)
	}

	fmt.Printf("User '%s' created with UID %d\n", username, uid)
}

func userExists(f *os.File, username string) bool {
	if _, err := f.Seek(0, 0); err != nil {
		return false
	}

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		parts := strings.Split(scanner.Text(), ":")
		if len(parts) > 0 && parts[0] == username {
			return true
		}
	}
	return false
}

func getNextUID(f *os.File) (int, int) {
	if _, err := f.Seek(0, 0); err != nil {
		return 1000, 1000
	}

	maxUID := 999
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		parts := strings.Split(scanner.Text(), ":")
		if len(parts) > 2 {
			uid, err := strconv.Atoi(parts[2])
			if err == nil && uid > maxUID {
				maxUID = uid
			}
		}
	}
	return maxUID + 1, maxUID + 1 // Use UID as GID for simplicity
}

