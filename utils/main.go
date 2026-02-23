package main

import (
	"fmt"
	"os"
	"path/filepath"

	"aulinux/shell"
	"aulinux/utils/cmd/aubuild"
	"aulinux/utils/cmd/cat"
	"aulinux/utils/cmd/chmod"
	"aulinux/utils/cmd/cp"
	"aulinux/utils/cmd/echo"
	"aulinux/utils/cmd/groupadd"
	"aulinux/utils/cmd/ip"
	"aulinux/utils/cmd/ls"
	"aulinux/utils/cmd/mkdir"
	"aulinux/utils/cmd/mv"
	"aulinux/utils/cmd/ps"
	"aulinux/utils/cmd/pwd"
	"aulinux/utils/cmd/rm"
	"aulinux/utils/cmd/useradd"
)

func main() {
	// Determine which tool to run based on argv[0]
	name := filepath.Base(os.Args[0])

	// If called as the multicall binary itself (e.g., "auutils"),
	// check if the first argument is a command.
	args := os.Args[1:]
	if name == "auutils" {
		if len(args) > 0 {
			name = args[0]
			args = args[1:]
		} else {
			// Default behavior: run shell if no args
			name = "aush"
		}
	}

	switch name {
	case "ls":
		ls.Run(args)
	case "cat":
		cat.Run(args)
	case "cp":
		cp.Run(args)
	case "mv":
		mv.Run(args)
	case "mkdir":
		mkdir.Run(args)
	case "rm":
		rm.Run(args)
	case "chmod":
		chmod.Run(args)
	case "echo":
		echo.Run(args)
	case "pwd":
		pwd.Run(args)
	case "ps":
		ps.Run(args)
	case "ip":
		ip.Run(args)
	case "useradd":
		useradd.Run(args)
	case "groupadd":
		groupadd.Run(args)
	case "aubuild":
		aubuild.Run(args)
	case "aush", "sh": // "sh" is often a symlink to the shell
		shell.Run(args)
	default:
		fmt.Fprintf(os.Stderr, "auutils: command not found: %s\n", name)
		os.Exit(1)
	}
}
