// Package main implements the echo command for AULinux.
// Displays a line of text.
package main

import (
	"flag"
	"fmt"
	"os"
	"strings"
)

const version = "1.0.0"

var (
	noNewline      = flag.Bool("n", false, "do not output trailing newline")
	enableEscapes  = flag.Bool("e", false, "enable interpretation of backslash escapes")
	disableEscapes = flag.Bool("E", false, "disable interpretation of backslash escapes (default)")
	showVersion    = flag.Bool("version", false, "show version")
)

func main() {
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: echo [OPTIONS] [STRING]...\n\n")
		fmt.Fprintf(os.Stderr, "Display a line of text.\n\n")
		fmt.Fprintf(os.Stderr, "Options:\n")
		flag.PrintDefaults()
		fmt.Fprintf(os.Stderr, "\nEscape sequences (with -e):\n")
		fmt.Fprintf(os.Stderr, "  \\\\    backslash\n")
		fmt.Fprintf(os.Stderr, "  \\n    new line\n")
		fmt.Fprintf(os.Stderr, "  \\t    horizontal tab\n")
		fmt.Fprintf(os.Stderr, "  \\r    carriage return\n")
	}
	flag.Parse()

	if *showVersion {
		fmt.Printf("echo (AULinux coreutils) %s\n", version)
		os.Exit(0)
	}

	output := strings.Join(flag.Args(), " ")

	if *enableEscapes {
		output = processEscapes(output)
	}

	fmt.Print(output)
	if !*noNewline {
		fmt.Println()
	}
}

func processEscapes(s string) string {
	var result strings.Builder
	i := 0
	for i < len(s) {
		if s[i] == '\\' && i+1 < len(s) {
			switch s[i+1] {
			case '\\':
				result.WriteByte('\\')
				i += 2
			case 'n':
				result.WriteByte('\n')
				i += 2
			case 't':
				result.WriteByte('\t')
				i += 2
			case 'r':
				result.WriteByte('\r')
				i += 2
			case 'a':
				result.WriteByte('\a')
				i += 2
			case 'b':
				result.WriteByte('\b')
				i += 2
			case 'f':
				result.WriteByte('\f')
				i += 2
			case 'v':
				result.WriteByte('\v')
				i += 2
			case '0':
				// Octal escape
				if i+2 < len(s) && s[i+2] >= '0' && s[i+2] <= '7' {
					val := 0
					j := i + 2
					for j < len(s) && j < i+5 && s[j] >= '0' && s[j] <= '7' {
						val = val*8 + int(s[j]-'0')
						j++
					}
					result.WriteByte(byte(val))
					i = j
				} else {
					result.WriteByte(0)
					i += 2
				}
			default:
				result.WriteByte(s[i])
				i++
			}
		} else {
			result.WriteByte(s[i])
			i++
		}
	}
	return result.String()
}
