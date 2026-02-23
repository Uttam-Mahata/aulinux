// Package cp implements the cp command for AULinux.
// Copies files and directories.
package cp

import (
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

const version = "1.0.0"

var (
	recursive   *bool
	recursiveR  *bool
	force       *bool
	interactive *bool
	verbose     *bool
	preserve    *bool
	noClobber   *bool
	showVersion *bool
)

func Run(args []string) {
	fs := flag.NewFlagSet("cp", flag.ExitOnError)
	recursive = fs.Bool("r", false, "copy directories recursively")
	recursiveR = fs.Bool("R", false, "copy directories recursively")
	force = fs.Bool("f", false, "overwrite without prompting")
	interactive = fs.Bool("i", false, "prompt before overwrite")
	verbose = fs.Bool("v", false, "explain what is being done")
	preserve = fs.Bool("p", false, "preserve mode, ownership and timestamps")
	noClobber = fs.Bool("n", false, "do not overwrite existing file")
	showVersion = fs.Bool("version", false, "show version")

	fs.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: cp [OPTIONS] SOURCE DEST\n")
		fmt.Fprintf(os.Stderr, "       cp [OPTIONS] SOURCE... DIRECTORY\n\n")
		fmt.Fprintf(os.Stderr, "Copy SOURCE to DEST, or multiple SOURCE(s) to DIRECTORY.\n\n")
		fmt.Fprintf(os.Stderr, "Options:\n")
		fs.PrintDefaults()
	}
	fs.Parse(args)

	if *showVersion {
		fmt.Printf("cp (AULinux coreutils) %s\n", version)
		os.Exit(0)
	}

	// -R is alias for -r
	if *recursiveR {
		*recursive = true
	}

	cliArgs := fs.Args()
	if len(cliArgs) < 2 {
		fmt.Fprintln(os.Stderr, "cp: missing file operand")
		os.Exit(1)
	}

	dest := cliArgs[len(cliArgs)-1]
	sources := cliArgs[:len(cliArgs)-1]

	destInfo, destErr := os.Stat(dest)
	destIsDir := destErr == nil && destInfo.IsDir()

	// Multiple sources require destination to be a directory
	if len(sources) > 1 && !destIsDir {
		fmt.Fprintln(os.Stderr, "cp: target is not a directory")
		os.Exit(1)
	}

	exitCode := 0
	for _, src := range sources {
		target := dest
		if destIsDir {
			target = filepath.Join(dest, filepath.Base(src))
		}

		if err := copyPath(src, target); err != nil {
			fmt.Fprintf(os.Stderr, "cp: %v\n", err)
			exitCode = 1
		}
	}

	if exitCode != 0 {
		os.Exit(exitCode)
	}
}

func copyPath(src, dest string) error {
	srcInfo, err := os.Lstat(src)
	if err != nil {
		return err
	}

	// Handle directories
	if srcInfo.IsDir() {
		if !*recursive {
			return fmt.Errorf("omitting directory '%s'", src)
		}
		return copyDir(src, dest, srcInfo)
	}

	// Handle symlinks
	if srcInfo.Mode()&os.ModeSymlink != 0 {
		return copySymlink(src, dest)
	}

	// Handle regular files
	return copyFile(src, dest, srcInfo)
}

func copyFile(src, dest string, srcInfo os.FileInfo) error {
	// Check if destination exists
	if _, err := os.Lstat(dest); err == nil {
		if *noClobber {
			return nil
		}
		if *interactive && !*force {
			fmt.Printf("cp: overwrite '%s'? ", dest)
			var response string
			fmt.Scanln(&response)
			if response != "y" && response != "Y" && response != "yes" {
				return nil
			}
		}
	}

	// Open source file
	srcFile, err := os.Open(src)
	if err != nil {
		return err
	}
	defer srcFile.Close()

	// Create destination file
	destFile, err := os.Create(dest)
	if err != nil {
		return err
	}
	defer destFile.Close()

	// Copy contents
	if _, err := io.Copy(destFile, srcFile); err != nil {
		return err
	}

	// Preserve permissions
	if *preserve {
		if err := os.Chmod(dest, srcInfo.Mode()); err != nil {
			return err
		}
		// Note: preserving ownership requires root privileges
	} else {
		if err := os.Chmod(dest, srcInfo.Mode()&0777); err != nil {
			return err
		}
	}

	if *verbose {
		fmt.Printf("'%s' -> '%s'\n", src, dest)
	}

	return nil
}

func copyDir(src, dest string, srcInfo os.FileInfo) error {
	// Create destination directory
	if err := os.MkdirAll(dest, srcInfo.Mode()); err != nil {
		return err
	}

	if *verbose {
		fmt.Printf("'%s' -> '%s'\n", src, dest)
	}

	// Read source directory
	entries, err := os.ReadDir(src)
	if err != nil {
		return err
	}

	// Copy each entry
	for _, entry := range entries {
		srcPath := filepath.Join(src, entry.Name())
		destPath := filepath.Join(dest, entry.Name())

		if err := copyPath(srcPath, destPath); err != nil {
			return err
		}
	}

	return nil
}

func copySymlink(src, dest string) error {
	link, err := os.Readlink(src)
	if err != nil {
		return err
	}

	// Remove existing destination if it exists
	if _, err := os.Lstat(dest); err == nil {
		if *noClobber {
			return nil
		}
		os.Remove(dest)
	}

	if err := os.Symlink(link, dest); err != nil {
		return err
	}

	if *verbose {
		fmt.Printf("'%s' -> '%s'\n", src, dest)
	}

	return nil
}
