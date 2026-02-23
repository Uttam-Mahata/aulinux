// Package echo implements the echo command for AULinux.
// Displays a line of text.
package echo

import (
	"flag"
	"fmt"
	"os"
	"strings"
)

const version = "1.0.0"

var (
	noNewline      *bool
	enableEscapes  *bool
	disableEscapes *bool
	showVersion    *bool
)

func Run(args []string) {
	fs := flag.NewFlagSet("echo", flag.ExitOnError)
	noNewline = fs.Bool("n", false, "do not output trailing newline")
	enableEscapes = fs.Bool("e", false, "enable interpretation of backslash escapes")
	disableEscapes = fs.Bool("E", false, "disable interpretation of backslash escapes (default)")
	showVersion = fs.Bool("version", false, "show version")

	fs.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: echo [OPTIONS] [STRING]...\n\n")
		fmt.Fprintf(os.Stderr, "Display a line of text.\n\n")
		fmt.Fprintf(os.Stderr, "Options:\n")
		fs.PrintDefaults()
		fmt.Fprintf(os.Stderr, "\nEscape sequences (with -e):\n")
		fmt.Fprintf(os.Stderr, "  \\\\    backslash\n")
		fmt.Fprintf(os.Stderr, "  \\n    new line\n")
		fmt.Fprintf(os.Stderr, "  \\t    horizontal tab\n")
		fmt.Fprintf(os.Stderr, "  \\r    carriage return\n")
	}
	fs.Parse(args)

	if *showVersion {
		fmt.Printf("echo (AULinux coreutils) %s\n", version)
		os.Exit(0)
	}

	output := strings.Join(fs.Args(), " ")

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
