// Package main implements the cat command for AULinux.
// Concatenates and displays file contents.
package main

import (
	"bufio"
	"flag"
	"fmt"
	"io"
	"os"
)

const version = "1.0.0"

var (
	showNumbers    = flag.Bool("n", false, "number all output lines")
	showNonBlank   = flag.Bool("b", false, "number non-blank output lines")
	showEnds       = flag.Bool("E", false, "display $ at end of each line")
	showTabs       = flag.Bool("T", false, "display TAB as ^I")
	squeezeBlank   = flag.Bool("s", false, "squeeze multiple blank lines")
	showNonPrint   = flag.Bool("v", false, "show non-printing characters")
	showVersion    = flag.Bool("version", false, "show version")
)

func main() {
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: cat [OPTIONS] [FILE]...\n\n")
		fmt.Fprintf(os.Stderr, "Concatenate FILE(s) to standard output.\n\n")
		fmt.Fprintf(os.Stderr, "With no FILE, or when FILE is -, read standard input.\n\n")
		fmt.Fprintf(os.Stderr, "Options:\n")
		flag.PrintDefaults()
	}
	flag.Parse()

	if *showVersion {
		fmt.Printf("cat (AULinux coreutils) %s\n", version)
		os.Exit(0)
	}

	// If -b is set, it overrides -n
	if *showNonBlank {
		*showNumbers = false
	}

	files := flag.Args()
	if len(files) == 0 {
		files = []string{"-"}
	}

	exitCode := 0
	for _, file := range files {
		if err := catFile(file); err != nil {
			fmt.Fprintf(os.Stderr, "cat: %s: %v\n", file, err)
			exitCode = 1
		}
	}

	os.Exit(exitCode)
}

func catFile(path string) error {
	var reader io.Reader

	if path == "-" {
		reader = os.Stdin
	} else {
		f, err := os.Open(path)
		if err != nil {
			return err
		}
		defer f.Close()
		reader = f
	}

	// Simple case: no formatting options
	if !*showNumbers && !*showNonBlank && !*showEnds && !*showTabs && !*squeezeBlank && !*showNonPrint {
		_, err := io.Copy(os.Stdout, reader)
		return err
	}

	// Formatted output
	scanner := bufio.NewScanner(reader)
	lineNum := 0
	prevBlank := false

	for scanner.Scan() {
		line := scanner.Text()
		isBlank := len(line) == 0

		// Squeeze blank lines
		if *squeezeBlank && isBlank && prevBlank {
			continue
		}
		prevBlank = isBlank

		// Line numbering
		if *showNumbers || (*showNonBlank && !isBlank) {
			lineNum++
			fmt.Printf("%6d\t", lineNum)
		}

		// Process line content
		output := line
		if *showTabs {
			output = replaceTabs(output)
		}
		if *showNonPrint {
			output = showNonPrintable(output)
		}

		fmt.Print(output)

		// End of line marker
		if *showEnds {
			fmt.Print("$")
		}
		fmt.Println()
	}

	return scanner.Err()
}

func replaceTabs(s string) string {
	result := ""
	for _, r := range s {
		if r == '\t' {
			result += "^I"
		} else {
			result += string(r)
		}
	}
	return result
}

func showNonPrintable(s string) string {
	result := ""
	for _, r := range s {
		if r == '\t' {
			result += string(r) // Let -T handle tabs
		} else if r < 32 {
			result += fmt.Sprintf("^%c", r+64)
		} else if r == 127 {
			result += "^?"
		} else if r > 127 {
			result += fmt.Sprintf("M-%c", r-128)
		} else {
			result += string(r)
		}
	}
	return result
}
