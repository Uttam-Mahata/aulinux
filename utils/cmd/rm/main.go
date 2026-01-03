// Package main implements the rm command for AULinux.
// Removes files and directories.
package main

import (
	"flag"
	"fmt"
	"os"
)

const version = "1.0.0"

var (
	force       = flag.Bool("f", false, "ignore nonexistent files, never prompt")
	interactive = flag.Bool("i", false, "prompt before every removal")
	recursive   = flag.Bool("r", false, "remove directories and their contents recursively")
	recursiveR  = flag.Bool("R", false, "remove directories and their contents recursively")
	verbose     = flag.Bool("v", false, "explain what is being done")
	dir         = flag.Bool("d", false, "remove empty directories")
	showVersion = flag.Bool("version", false, "show version")
)

func main() {
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: rm [OPTIONS] FILE...\n\n")
		fmt.Fprintf(os.Stderr, "Remove (unlink) the FILE(s).\n\n")
		fmt.Fprintf(os.Stderr, "Options:\n")
		flag.PrintDefaults()
	}
	flag.Parse()

	if *showVersion {
		fmt.Printf("rm (AULinux coreutils) %s\n", version)
		os.Exit(0)
	}

	// -R is alias for -r
	if *recursiveR {
		*recursive = true
	}

	if flag.NArg() == 0 {
		fmt.Fprintln(os.Stderr, "rm: missing operand")
		os.Exit(1)
	}

	exitCode := 0
	for _, path := range flag.Args() {
		if err := remove(path); err != nil {
			if !*force {
				fmt.Fprintf(os.Stderr, "rm: %v\n", err)
				exitCode = 1
			}
		}
	}

	os.Exit(exitCode)
}

func remove(path string) error {
	info, err := os.Lstat(path)
	if err != nil {
		if os.IsNotExist(err) && *force {
			return nil
		}
		return err
	}

	// Check if it's a directory
	if info.IsDir() {
		if !*recursive && !*dir {
			return fmt.Errorf("cannot remove '%s': Is a directory", path)
		}

		if *dir && !*recursive {
			// Only remove empty directories
			entries, err := os.ReadDir(path)
			if err != nil {
				return err
			}
			if len(entries) > 0 {
				return fmt.Errorf("cannot remove '%s': Directory not empty", path)
			}
		}
	}

	// Interactive mode
	if *interactive {
		fmt.Printf("rm: remove %s '%s'? ", fileType(info), path)
		var response string
		fmt.Scanln(&response)
		if response != "y" && response != "Y" && response != "yes" {
			return nil
		}
	}

	// Perform removal
	if *recursive && info.IsDir() {
		err = removeRecursive(path)
	} else {
		err = os.Remove(path)
	}

	if err != nil {
		return err
	}

	if *verbose {
		fmt.Printf("removed '%s'\n", path)
	}

	return nil
}

func removeRecursive(path string) error {
	return os.RemoveAll(path)
}

func fileType(info os.FileInfo) string {
	mode := info.Mode()
	switch {
	case mode.IsDir():
		return "directory"
	case mode&os.ModeSymlink != 0:
		return "symbolic link"
	default:
		return "file"
	}
}
