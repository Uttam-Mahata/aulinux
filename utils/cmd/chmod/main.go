// Package main implements the chmod command for AULinux.
// Changes file mode bits.
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
)

const version = "1.0.0"

var (
	recursive   = flag.Bool("R", false, "change files and directories recursively")
	verbose     = flag.Bool("v", false, "output a diagnostic for every file processed")
	showVersion = flag.Bool("version", false, "show version")
)

func main() {
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: chmod [OPTIONS] MODE FILE...\n")
		fmt.Fprintf(os.Stderr, "Change the mode of each FILE to MODE.\n\n")
		fmt.Fprintf(os.Stderr, "Options:\n")
		flag.PrintDefaults()
	}
	flag.Parse()

	if *showVersion {
		fmt.Printf("chmod (AULinux coreutils) %s\n", version)
		os.Exit(0)
	}

	args := flag.Args()
	if len(args) < 2 {
		fmt.Fprintln(os.Stderr, "chmod: missing operand")
		os.Exit(1)
	}

	modeStr := args[0]
	files := args[1:]

	// Parse mode
	// TODO: Support symbolic modes (e.g. u+x)
	mode, err := strconv.ParseUint(modeStr, 8, 32)
	if err != nil {
		fmt.Fprintf(os.Stderr, "chmod: invalid mode: '%s' (only octal supported)\n", modeStr)
		os.Exit(1)
	}
	fileMode := os.FileMode(mode)

	exitCode := 0
	for _, file := range files {
		if err := changeMode(file, fileMode); err != nil {
			fmt.Fprintf(os.Stderr, "chmod: cannot access '%s': %v\n", file, err)
			exitCode = 1
		}
	}

	os.Exit(exitCode)
}

func changeMode(path string, mode os.FileMode) error {
	if !*recursive {
		if *verbose {
			fmt.Printf("mode of '%s' changed to %04o\n", path, mode)
		}
		return os.Chmod(path, mode)
	}

	return filepath.Walk(path, func(p string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if *verbose {
			fmt.Printf("mode of '%s' changed to %04o\n", p, mode)
		}
		return os.Chmod(p, mode)
	})
}
