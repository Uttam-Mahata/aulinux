// Package mkdir implements the mkdir command for AULinux.
// Creates directories.
package mkdir

import (
	"flag"
	"fmt"
	"os"
	"strconv"
)

const version = "1.0.0"

var (
	makeParents *bool
	mode        *string
	verbose     *bool
	showVersion *bool
)

func Run(args []string) {
	fs := flag.NewFlagSet("mkdir", flag.ExitOnError)
	makeParents = fs.Bool("p", false, "make parent directories as needed")
	mode = fs.String("m", "", "set file mode (as in chmod)")
	verbose = fs.Bool("v", false, "print a message for each created directory")
	showVersion = fs.Bool("version", false, "show version")

	fs.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: mkdir [OPTIONS] DIRECTORY...\n\n")
		fmt.Fprintf(os.Stderr, "Create the DIRECTORY(ies), if they do not already exist.\n\n")
		fmt.Fprintf(os.Stderr, "Options:\n")
		fs.PrintDefaults()
	}
	fs.Parse(args)

	if *showVersion {
		fmt.Printf("mkdir (AULinux coreutils) %s\n", version)
		os.Exit(0)
	}

	if fs.NArg() == 0 {
		fmt.Fprintln(os.Stderr, "mkdir: missing operand")
		os.Exit(1)
	}

	// Parse mode
	perm := os.FileMode(0755)
	if *mode != "" {
		m, err := strconv.ParseUint(*mode, 8, 32)
		if err != nil {
			fmt.Fprintf(os.Stderr, "mkdir: invalid mode '%s'\n", *mode)
			os.Exit(1)
		}
		perm = os.FileMode(m)
	}

	exitCode := 0
	for _, dir := range fs.Args() {
		if err := makeDir(dir, perm); err != nil {
			fmt.Fprintf(os.Stderr, "mkdir: %v\n", err)
			exitCode = 1
		}
	}

	if exitCode != 0 {
		os.Exit(exitCode)
	}
}

func makeDir(path string, perm os.FileMode) error {
	var err error

	if *makeParents {
		err = os.MkdirAll(path, perm)
	} else {
		err = os.Mkdir(path, perm)
	}

	if err != nil {
		return err
	}

	if *verbose {
		fmt.Printf("mkdir: created directory '%s'\n", path)
	}

	return nil
}
