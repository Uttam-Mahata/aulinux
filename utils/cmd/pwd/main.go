// Package pwd implements the pwd command for AULinux.
// Prints the current working directory.
package pwd

import (
	"flag"
	"fmt"
	"os"
)

const version = "1.0.0"

var (
	logical     *bool
	physical    *bool
	showVersion *bool
)

func Run(args []string) {
	fs := flag.NewFlagSet("pwd", flag.ExitOnError)
	logical = fs.Bool("L", false, "use PWD from environment, even if it contains symlinks")
	physical = fs.Bool("P", false, "avoid all symlinks (default)")
	showVersion = fs.Bool("version", false, "show version")

	fs.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: pwd [OPTIONS]\n\n")
		fmt.Fprintf(os.Stderr, "Print the full filename of the current working directory.\n\n")
		fmt.Fprintf(os.Stderr, "Options:\n")
		fs.PrintDefaults()
	}
	fs.Parse(args)

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
