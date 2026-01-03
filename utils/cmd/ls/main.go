// Package main implements the ls command for AULinux.
// Lists directory contents with color and detailed output support.
package main

import (
	"flag"
	"fmt"
	"io/fs"
	"os"
	"os/user"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"text/tabwriter"
	"time"
)

const version = "1.0.0"

var (
	longFormat  = flag.Bool("l", false, "use long listing format")
	showAll     = flag.Bool("a", false, "show hidden files (starting with .)")
	showAlmost  = flag.Bool("A", false, "show hidden files except . and ..")
	humanSize   = flag.Bool("h", false, "human-readable sizes (with -l)")
	sortByTime  = flag.Bool("t", false, "sort by modification time")
	sortBySize  = flag.Bool("S", false, "sort by file size")
	reverseSort = flag.Bool("r", false, "reverse sort order")
	noColor     = flag.Bool("no-color", false, "disable color output")
	showVersion = flag.Bool("version", false, "show version")
)

// ANSI color codes
const (
	colorReset   = "\033[0m"
	colorDir     = "\033[1;34m" // bold blue
	colorExec    = "\033[1;32m" // bold green
	colorSymlink = "\033[1;36m" // bold cyan
	colorArchive = "\033[1;31m" // bold red
	colorImage   = "\033[1;35m" // bold magenta
)

func main() {
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: ls [OPTIONS] [FILE]...\n\n")
		fmt.Fprintf(os.Stderr, "List directory contents.\n\n")
		fmt.Fprintf(os.Stderr, "Options:\n")
		flag.PrintDefaults()
	}
	flag.Parse()

	if *showVersion {
		fmt.Printf("ls (AULinux coreutils) %s\n", version)
		os.Exit(0)
	}

	// Determine paths to list
	paths := flag.Args()
	if len(paths) == 0 {
		paths = []string{"."}
	}

	// Check if stdout is a terminal
	isTTY := isTerminal(os.Stdout)
	useColor := isTTY && !*noColor

	exitCode := 0
	for i, path := range paths {
		if len(paths) > 1 {
			if i > 0 {
				fmt.Println()
			}
			fmt.Printf("%s:\n", path)
		}

		if err := listDir(path, useColor); err != nil {
			fmt.Fprintf(os.Stderr, "ls: %s: %v\n", path, err)
			exitCode = 1
		}
	}

	os.Exit(exitCode)
}

func isTerminal(f *os.File) bool {
	fi, err := f.Stat()
	if err != nil {
		return false
	}
	return (fi.Mode() & os.ModeCharDevice) != 0
}

func listDir(path string, useColor bool) error {
	info, err := os.Lstat(path)
	if err != nil {
		return err
	}

	// If it's a file, just list it
	if !info.IsDir() {
		if *longFormat {
			printLong(path, info, useColor)
		} else {
			printName(info.Name(), info, useColor)
			fmt.Println()
		}
		return nil
	}

	// Read directory entries
	entries, err := os.ReadDir(path)
	if err != nil {
		return err
	}

	// Filter entries
	var filtered []fs.DirEntry
	for _, entry := range entries {
		name := entry.Name()
		if !*showAll && !*showAlmost && strings.HasPrefix(name, ".") {
			continue
		}
		if *showAlmost && (name == "." || name == "..") {
			continue
		}
		filtered = append(filtered, entry)
	}

	// Get file info for sorting
	type entryInfo struct {
		entry fs.DirEntry
		info  fs.FileInfo
	}
	var infos []entryInfo
	for _, entry := range filtered {
		info, err := entry.Info()
		if err != nil {
			continue
		}
		infos = append(infos, entryInfo{entry, info})
	}

	// Sort entries
	sort.Slice(infos, func(i, j int) bool {
		var less bool
		if *sortByTime {
			less = infos[i].info.ModTime().After(infos[j].info.ModTime())
		} else if *sortBySize {
			less = infos[i].info.Size() > infos[j].info.Size()
		} else {
			less = strings.ToLower(infos[i].entry.Name()) < strings.ToLower(infos[j].entry.Name())
		}
		if *reverseSort {
			less = !less
		}
		return less
	})

	// Print entries
	if *longFormat {
		w := tabwriter.NewWriter(os.Stdout, 0, 0, 1, ' ', 0)
		for _, ei := range infos {
			printLongTab(w, filepath.Join(path, ei.entry.Name()), ei.info, useColor)
		}
		w.Flush()
	} else {
		for _, ei := range infos {
			printName(ei.entry.Name(), ei.info, useColor)
			fmt.Print("  ")
		}
		if len(infos) > 0 {
			fmt.Println()
		}
	}

	return nil
}

func printLong(path string, info fs.FileInfo, useColor bool) {
	w := tabwriter.NewWriter(os.Stdout, 0, 0, 1, ' ', 0)
	printLongTab(w, path, info, useColor)
	w.Flush()
}

func printLongTab(w *tabwriter.Writer, path string, info fs.FileInfo, useColor bool) {
	mode := info.Mode()
	
	// Get owner/group (Unix-specific)
	var owner, group string
	if stat, ok := info.Sys().(*syscall.Stat_t); ok {
		if u, err := user.LookupId(strconv.Itoa(int(stat.Uid))); err == nil {
			owner = u.Username
		} else {
			owner = strconv.Itoa(int(stat.Uid))
		}
		if g, err := user.LookupGroupId(strconv.Itoa(int(stat.Gid))); err == nil {
			group = g.Name
		} else {
			group = strconv.Itoa(int(stat.Gid))
		}
	} else {
		owner = "?"
		group = "?"
	}

	// Format size
	size := formatSize(info.Size())

	// Format time
	modTime := info.ModTime()
	var timeStr string
	if time.Since(modTime) > 6*30*24*time.Hour {
		timeStr = modTime.Format("Jan _2  2006")
	} else {
		timeStr = modTime.Format("Jan _2 15:04")
	}

	// Get name with color
	name := colorize(info.Name(), info, useColor)

	// Handle symlinks
	if mode&os.ModeSymlink != 0 {
		if target, err := os.Readlink(path); err == nil {
			name += " -> " + target
		}
	}

	fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\t%s\n",
		mode.String(), owner, group, size, timeStr, name)
}

func printName(name string, info fs.FileInfo, useColor bool) {
	fmt.Print(colorize(name, info, useColor))
}

func colorize(name string, info fs.FileInfo, useColor bool) string {
	if !useColor {
		return name
	}

	mode := info.Mode()
	var color string

	switch {
	case mode.IsDir():
		color = colorDir
	case mode&os.ModeSymlink != 0:
		color = colorSymlink
	case mode&0111 != 0:
		color = colorExec
	case isArchive(name):
		color = colorArchive
	case isImage(name):
		color = colorImage
	default:
		return name
	}

	return color + name + colorReset
}

func formatSize(size int64) string {
	if !*humanSize {
		return fmt.Sprintf("%d", size)
	}

	const unit = 1024
	if size < unit {
		return fmt.Sprintf("%d", size)
	}
	div, exp := int64(unit), 0
	for n := size / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f%c", float64(size)/float64(div), "KMGTPE"[exp])
}

func isArchive(name string) bool {
	exts := []string{".tar", ".gz", ".zip", ".bz2", ".xz", ".7z", ".rar"}
	lower := strings.ToLower(name)
	for _, ext := range exts {
		if strings.HasSuffix(lower, ext) {
			return true
		}
	}
	return false
}

func isImage(name string) bool {
	exts := []string{".jpg", ".jpeg", ".png", ".gif", ".bmp", ".svg", ".webp"}
	lower := strings.ToLower(name)
	for _, ext := range exts {
		if strings.HasSuffix(lower, ext) {
			return true
		}
	}
	return false
}
