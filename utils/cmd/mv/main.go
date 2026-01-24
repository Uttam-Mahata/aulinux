// Package main implements the mv command for AULinux.
// Moves (renames) files.
package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"syscall"
)

const version = "1.0.0"

var (
	force       = flag.Bool("f", false, "do not prompt before overwriting")
	interactive = flag.Bool("i", false, "prompt before overwrite")
	verbose     = flag.Bool("v", false, "explain what is being done")
	noClobber   = flag.Bool("n", false, "do not overwrite an existing file")
	showVersion = flag.Bool("version", false, "show version")
)

func main() {
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: mv [OPTIONS] SOURCE DEST\n")
		fmt.Fprintf(os.Stderr, "       mv [OPTIONS] SOURCE... DIRECTORY\n\n")
		fmt.Fprintf(os.Stderr, "Rename SOURCE to DEST, or move SOURCE(s) to DIRECTORY.\n\n")
		fmt.Fprintf(os.Stderr, "Options:\n")
		flag.PrintDefaults()
	}
	flag.Parse()

	if *showVersion {
		fmt.Printf("mv (AULinux coreutils) %s\n", version)
		os.Exit(0)
	}

	args := flag.Args()
	if len(args) < 2 {
		fmt.Fprintln(os.Stderr, "mv: missing file operand")
		os.Exit(1)
	}

	dest := args[len(args)-1]
	sources := args[:len(args)-1]

	destInfo, destErr := os.Stat(dest)
	destIsDir := destErr == nil && destInfo.IsDir()

	// Multiple sources require destination to be a directory
	if len(sources) > 1 && !destIsDir {
		fmt.Fprintf(os.Stderr, "mv: target '%s' is not a directory\n", dest)
		os.Exit(1)
	}

	exitCode := 0
	for _, src := range sources {
		target := dest
		if destIsDir {
			target = filepath.Join(dest, filepath.Base(src))
		}

		if err := movePath(src, target); err != nil {
			fmt.Fprintf(os.Stderr, "mv: cannot move '%s' to '%s': %v\n", src, target, err)
			exitCode = 1
		}
	}

	os.Exit(exitCode)
}

func movePath(src, dest string) error {
	// Check if source exists
	if _, err := os.Lstat(src); err != nil {
		return err
	}

	// Check if destination exists
	if _, err := os.Lstat(dest); err == nil {
		if *noClobber {
			return nil
		}
		if *interactive && !*force {
			fmt.Printf("mv: overwrite '%s'? ", dest)
			var response string
			fmt.Scanln(&response)
			response = strings.ToLower(strings.TrimSpace(response))
			if response != "y" && response != "yes" {
				return nil
			}
		}
	}

	// Try atomic rename
	err := os.Rename(src, dest)
	if err == nil {
		if *verbose {
			fmt.Printf("'%s' -> '%s'\n", src, dest)
		}
		return nil
	}

	// Check for cross-device link
	if linkErr, ok := err.(*os.LinkError); ok {
		if linkErr.Err == syscall.EXDEV {
			return moveCrossDevice(src, dest)
		}
	}

	return err
}

func moveCrossDevice(src, dest string) error {
	// Simple copy and delete
	srcFile, err := os.Open(src)
	if err != nil {
		return err
	}
	defer srcFile.Close()

	srcInfo, err := srcFile.Stat()
	if err != nil {
		return err
	}

	if srcInfo.IsDir() {
		return fmt.Errorf("cross-device directory move not implemented")
	}

	destFile, err := os.Create(dest)
	if err != nil {
		return err
	}
	defer destFile.Close()

	if _, err := io.Copy(destFile, srcFile); err != nil {
		return err
	}

	// Preserve permissions
	if err := os.Chmod(dest, srcInfo.Mode()); err != nil {
		return err
	}

	// Delete source
	srcFile.Close() // Ensure closed before remove
	if err := os.Remove(src); err != nil {
		return fmt.Errorf("failed to remove source after copy: %v", err)
	}

	if *verbose {
		fmt.Printf("'%s' -> '%s'\n", src, dest)
	}

	return nil
}
