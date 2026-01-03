// Package main implements the mv command for AULinux.
// Moves or renames files and directories.
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
)

const version = "1.0.0"

var (
	force       = flag.Bool("f", false, "do not prompt before overwriting")
	interactive = flag.Bool("i", false, "prompt before overwrite")
	noClobber   = flag.Bool("n", false, "do not overwrite an existing file")
	verbose     = flag.Bool("v", false, "explain what is being done")
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
		fmt.Fprintln(os.Stderr, "mv: target is not a directory")
		os.Exit(1)
	}

	exitCode := 0
	for _, src := range sources {
		target := dest
		if destIsDir {
			target = filepath.Join(dest, filepath.Base(src))
		}

		if err := moveFile(src, target); err != nil {
			fmt.Fprintf(os.Stderr, "mv: %v\n", err)
			exitCode = 1
		}
	}

	os.Exit(exitCode)
}

func moveFile(src, dest string) error {
	// Check if source exists
	srcInfo, err := os.Lstat(src)
	if err != nil {
		return err
	}

	// Check if destination exists
	destExists := false
	if _, err := os.Lstat(dest); err == nil {
		destExists = true

		if *noClobber {
			return nil
		}

		if *interactive && !*force {
			fmt.Printf("mv: overwrite '%s'? ", dest)
			var response string
			fmt.Scanln(&response)
			if response != "y" && response != "Y" && response != "yes" {
				return nil
			}
		}
	}

	// Try to rename (works for same filesystem)
	err = os.Rename(src, dest)
	if err == nil {
		if *verbose {
			if destExists {
				fmt.Printf("'%s' -> '%s' (overwritten)\n", src, dest)
			} else {
				fmt.Printf("'%s' -> '%s'\n", src, dest)
			}
		}
		return nil
	}

	// If rename fails (cross-device), fall back to copy and delete
	if !isLinkError(err) {
		return err
	}

	// Copy the file/directory
	if srcInfo.IsDir() {
		if err := copyDir(src, dest); err != nil {
			return err
		}
	} else {
		if err := copyFile(src, dest); err != nil {
			return err
		}
	}

	// Remove the source
	if err := os.RemoveAll(src); err != nil {
		return fmt.Errorf("failed to remove source after copy: %v", err)
	}

	if *verbose {
		fmt.Printf("'%s' -> '%s'\n", src, dest)
	}

	return nil
}

// isLinkError checks if the error is a cross-device link error
func isLinkError(err error) bool {
	if linkErr, ok := err.(*os.LinkError); ok {
		return linkErr.Err.Error() == "invalid cross-device link"
	}
	return false
}

func copyFile(src, dest string) error {
	srcFile, err := os.Open(src)
	if err != nil {
		return err
	}
	defer srcFile.Close()

	srcInfo, err := srcFile.Stat()
	if err != nil {
		return err
	}

	destFile, err := os.OpenFile(dest, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, srcInfo.Mode())
	if err != nil {
		return err
	}
	defer destFile.Close()

	buf := make([]byte, 32*1024)
	for {
		n, err := srcFile.Read(buf)
		if n > 0 {
			if _, werr := destFile.Write(buf[:n]); werr != nil {
				return werr
			}
		}
		if err != nil {
			if err.Error() == "EOF" {
				break
			}
			return err
		}
	}

	return nil
}

func copyDir(src, dest string) error {
	srcInfo, err := os.Stat(src)
	if err != nil {
		return err
	}

	if err := os.MkdirAll(dest, srcInfo.Mode()); err != nil {
		return err
	}

	entries, err := os.ReadDir(src)
	if err != nil {
		return err
	}

	for _, entry := range entries {
		srcPath := filepath.Join(src, entry.Name())
		destPath := filepath.Join(dest, entry.Name())

		info, err := entry.Info()
		if err != nil {
			return err
		}

		if info.IsDir() {
			if err := copyDir(srcPath, destPath); err != nil {
				return err
			}
		} else {
			if err := copyFile(srcPath, destPath); err != nil {
				return err
			}
		}
	}

	return nil
}
