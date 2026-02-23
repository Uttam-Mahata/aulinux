package groupadd

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

const groupFile = "/etc/group"

func Run(args []string) {
	if len(args) < 1 {
		fmt.Println("Usage: groupadd <groupname>")
		os.Exit(1)
	}

	groupname := args[0]

	if groupExists(groupname) {
		fmt.Printf("Group '%s' already exists\n", groupname)
		os.Exit(1)
	}

    gid := getNextGID()

    // Format: groupname:x:GID:
    entry := fmt.Sprintf("%s:x:%d:\n", groupname, gid)

    f, err := os.OpenFile(groupFile, os.O_APPEND|os.O_WRONLY, 0644)
    if err != nil {
        fmt.Printf("Error opening %s: %v\n", groupFile, err)
        os.Exit(1)
    }
    defer f.Close()

    if _, err := f.WriteString(entry); err != nil {
        fmt.Printf("Error writing to %s: %v\n", groupFile, err)
        os.Exit(1)
    }

    fmt.Printf("Group '%s' created with GID %d\n", groupname, gid)
}

func groupExists(name string) bool {
    f, err := os.Open(groupFile)
    if err != nil {
        return false
    }
    defer f.Close()

    scanner := bufio.NewScanner(f)
    for scanner.Scan() {
        parts := strings.Split(scanner.Text(), ":")
        if len(parts) > 0 && parts[0] == name {
            return true
        }
    }
    return false
}

func getNextGID() int {
	f, err := os.Open(groupFile)
	if err != nil {
		return 1000
	}
	defer f.Close()

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
