// Package main implements the pwd command for AULinux.
// Prints the current working directory.
package main

import (
	"flag"
	"fmt"
	"os"
)

const version = "1.0.0"

var (
	logical     = flag.Bool("L", false, "use PWD from environment, even if it contains symlinks")
	physical    = flag.Bool("P", false, "avoid all symlinks (default)")
	showVersion = flag.Bool("version", false, "show version")
)

func main() {
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: pwd [OPTIONS]\n\n")
		fmt.Fprintf(os.Stderr, "Print the full filename of the current working directory.\n\n")
		fmt.Fprintf(os.Stderr, "Options:\n")
		flag.PrintDefaults()
	}
	flag.Parse()

	if *showVersion {
		fmt.Printf("pwd (AULinux coreutils) %s\n", version)
		os.Exit(0)
	}

	var dir string
	var err error

	if *logical {
		// Use PWD environment variable
		dir = os.Getenv("PWD")
		if dir == "" {
			dir, err = os.Getwd()
		}
	} else {
		// Physical path (resolve symlinks)
		dir, err = os.Getwd()
	}

	if err != nil {
		fmt.Fprintf(os.Stderr, "pwd: %v\n", err)
		os.Exit(1)
	}

	fmt.Println(dir)
}
