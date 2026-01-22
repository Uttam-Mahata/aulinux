package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

const passwdFile = "/etc/passwd"

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: useradd <username>")
		os.Exit(1)
	}

	username := os.Args[1]

	// Check if user exists
	if userExists(username) {
		fmt.Printf("User '%s' already exists\n", username)
		os.Exit(1)
	}

	// Find next UID
	uid, gid := getNextUID()

	// Append to /etc/passwd
	// Format: username:x:UID:GID:gecos:home:shell
	entry := fmt.Sprintf("%s:x:%d:%d:%s:/home/%s:/bin/aush\n", username, uid, gid, username, username)

	f, err := os.OpenFile(passwdFile, os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		fmt.Printf("Error opening %s: %v\n", passwdFile, err)
		os.Exit(1)
	}
	defer f.Close()

	if _, err := f.WriteString(entry); err != nil {
		fmt.Printf("Error writing to %s: %v\n", passwdFile, err)
		os.Exit(1)
	}

	fmt.Printf("User '%s' created with UID %d\n", username, uid)
}

func userExists(username string) bool {
	f, err := os.Open(passwdFile)
	if err != nil {
		return false
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		parts := strings.Split(scanner.Text(), ":")
		if len(parts) > 0 && parts[0] == username {
			return true
		}
	}
	return false
}

func getNextUID() (int, int) {
	f, err := os.Open(passwdFile)
	if err != nil {
		return 1000, 1000
	}
	defer f.Close()

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
