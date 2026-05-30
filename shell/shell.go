// Package shell implements aush - the Absolutely Unique Shell for AULinux.
// A modern, user-friendly shell with essential features.
package shell

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"os/user"
	"path/filepath"
	"strings"
	"syscall"
)

const (
	version     = "1.0.0"
	shellName   = "aush"
	historyFile = ".aush_history"
	maxHistory  = 1000
)

// JobState represents the state of a job
type JobState int

const (
	JobRunning JobState = iota
	JobStopped
	JobDone
	JobTerminated
)

func (js JobState) String() string {
	switch js {
	case JobRunning:
		return "Running"
	case JobStopped:
		return "Stopped"
	case JobDone:
		return "Done"
	case JobTerminated:
		return "Terminated"
	default:
		return "Unknown"
	}
}

// Job represents a background job
type Job struct {
	ID       int
	PID      int
	Command  string
	State    JobState
	Process  *os.Process
	DoneChan chan struct{}
}

// Shell represents the shell state
type Shell struct {
	user       *user.User
	hostname   string
	history    []string
	historyPos int
	exitCode   int
	running    bool
	loginShell bool
	jobs       []*Job
	nextJobID  int
}

// Builtins maps builtin command names to their implementations
var builtins map[string]func(*Shell, []string) int

func init() {
	builtins = map[string]func(*Shell, []string) int{
		"cd":      builtinCd,
		"exit":    builtinExit,
		"export":  builtinExport,
		"unset":   builtinUnset,
		"pwd":     builtinPwd,
		"echo":    builtinEcho,
		"history": builtinHistory,
		"help":    builtinHelp,
		"version": builtinVersion,
		"type":    builtinType,
		"jobs":    builtinJobs,
		"fg":      builtinFg,
		"bg":      builtinBg,
	}
}

func Run(args []string) {
	shell := NewShell()

	scriptFile := ""

	// Parse arguments
	for i := 0; i < len(args); i++ {
		arg := args[i]
		switch arg {
		case "-l", "--login":
			shell.loginShell = true
		case "-c":
			if i+1 < len(args) {
				os.Exit(shell.ExecuteCommand(args[i+1]))
			}
			fmt.Fprintln(os.Stderr, "aush: -c requires an argument")
			os.Exit(1)
		case "--version":
			fmt.Printf("aush (AULinux Shell) %s\n", version)
			os.Exit(0)
		case "--help":
			printHelp()
			os.Exit(0)
		default:
			if !strings.HasPrefix(arg, "-") && scriptFile == "" {
				scriptFile = arg
			}
		}
	}

	if scriptFile != "" {
		os.Exit(shell.RunScript(scriptFile))
	}

	// Run shell
	os.Exit(shell.Start())
}


// NewShell creates a new shell instance
func NewShell() *Shell {
	s := &Shell{
		running:    true,
		history:    make([]string, 0, maxHistory),
		historyPos: 0,
		jobs:       make([]*Job, 0),
		nextJobID:  1,
	}

	// Get current user
	if u, err := user.Current(); err == nil {
		s.user = u
	}

	// Get hostname
	if h, err := os.Hostname(); err == nil {
		s.hostname = h
	} else {
		s.hostname = "localhost"
	}

	// Ensure essential environment variables are set
	if os.Getenv("PATH") == "" {
		os.Setenv("PATH", "/bin:/sbin:/usr/bin:/usr/sbin")
	}
	if os.Getenv("HOME") == "" {
		os.Setenv("HOME", "/root")
	}
	if os.Getenv("USER") == "" {
		os.Setenv("USER", "root")
	}
	if os.Getenv("SHELL") == "" {
		os.Setenv("SHELL", "/bin/aush")
	}

	// Load history
	s.loadHistory()

	return s
}

// Start starts the main shell loop
func (s *Shell) Start() int {
	// Setup signal handlers
	s.setupSignals()

	// Print welcome message
	s.printWelcome()

	// Main loop
	reader := bufio.NewReader(os.Stdin)
	for s.running {
		// Print prompt
		s.printPrompt()

		// Read input
		line, err := reader.ReadString('\n')
		if err != nil {
			if err == io.EOF {
				fmt.Println()
				break
			}
			continue
		}

		// Process input
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		// Add to history
		s.addHistory(line)

		// Execute command
		s.exitCode = s.ExecuteCommand(line)
	}

	// Save history
	s.saveHistory()

	return s.exitCode
}

// RunScript opens a shell script file, reads it line by line, and executes it.
func (s *Shell) RunScript(filename string) int {
	file, err := os.Open(filename)
	if err != nil {
		fmt.Fprintf(os.Stderr, "aush: %v\n", err)
		return 1
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	lastExit := 0
	exitOnError := false
outer:
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		// Skip empty lines and comments
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		// Handle set -e
		if line == "set -e" {
			exitOnError = true
			continue
		}
		lastExit = s.ExecuteCommand(line)
		if exitOnError && lastExit != 0 {
			break outer
		}
	}
	if err := scanner.Err(); err != nil {
		fmt.Fprintf(os.Stderr, "aush: error reading script %s: %v\n", filename, err)
		return 1
	}
	return lastExit
}

// ExecuteCommand parses and executes a command line
func (s *Shell) ExecuteCommand(line string) int {
	// Handle pipes
	if strings.Contains(line, "|") {
		return s.executePipeline(line)
	}

	// Parse command
	args := s.parseCommand(line)
	if len(args) == 0 {
		return 0
	}

	// Check for background task
	background := false
	if len(args) > 0 && args[len(args)-1] == "&" {
		background = true
		args = args[:len(args)-1]
		if len(args) == 0 {
			return 0
		}
	}

	// Handle redirections
	args, stdin, stdout, stderr, err := s.parseRedirections(args)
	if err != nil {
		fmt.Fprintf(os.Stderr, "aush: %v\n", err)
		return 1
	}
	defer func() {
		if stdin != nil && stdin != os.Stdin {
			stdin.Close()
		}
		if stdout != nil && stdout != os.Stdout {
			stdout.Close()
		}
		if stderr != nil && stderr != os.Stderr {
			stderr.Close()
		}
	}()

	// Expand variables
	args = s.expandVariables(args)

	// Check for builtin
	if builtin, ok := builtins[args[0]]; ok {
		return builtin(s, args[1:])
	}

	// Execute external command
	return s.executeExternal(args, stdin, stdout, stderr, background)
}

// parseCommand splits a command line into arguments.
// quoteChar == 0 means not inside a quoted string; non-zero holds the opening quote rune.
func (s *Shell) parseCommand(line string) []string {
	var args []string
	var current strings.Builder
	var quoteChar rune // 0 = not in quote; '"' or '\'' = in that quote type

	runes := []rune(line)
	for i := 0; i < len(runes); i++ {
		c := runes[i]

		if quoteChar != 0 {
			// Inside a quoted section – end on matching close quote
			if c == quoteChar {
				quoteChar = 0
			} else {
				current.WriteRune(c)
			}
		} else {
			switch c {
			case '"', '\'':
				// Start a new quoted section
				quoteChar = c
			case ' ', '\t':
				if current.Len() > 0 {
					args = append(args, current.String())
					current.Reset()
				}
			case '&':
				if current.Len() > 0 {
					args = append(args, current.String())
					current.Reset()
				}
				args = append(args, "&")
			case '\\':
				if i+1 < len(runes) {
					i++
					current.WriteRune(runes[i])
				}
			default:
				current.WriteRune(c)
			}
		}
	}

	if current.Len() > 0 {
		args = append(args, current.String())
	}

	return args
}

// parseRedirections handles I/O redirection
func (s *Shell) parseRedirections(args []string) ([]string, *os.File, *os.File, *os.File, error) {
	stdin := os.Stdin
	stdout := os.Stdout
	stderr := os.Stderr

	var newArgs []string
	for i := 0; i < len(args); i++ {
		arg := args[i]

		switch {
		case arg == "<":
			if i+1 >= len(args) {
				return nil, nil, nil, nil, fmt.Errorf("syntax error near '<'")
			}
			i++
			f, err := os.Open(args[i])
			if err != nil {
				return nil, nil, nil, nil, err
			}
			stdin = f

		case arg == ">":
			if i+1 >= len(args) {
				return nil, nil, nil, nil, fmt.Errorf("syntax error near '>'")
			}
			i++
			f, err := os.Create(args[i])
			if err != nil {
				return nil, nil, nil, nil, err
			}
			stdout = f

		case arg == ">>":
			if i+1 >= len(args) {
				return nil, nil, nil, nil, fmt.Errorf("syntax error near '>>'")
			}
			i++
			f, err := os.OpenFile(args[i], os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
			if err != nil {
				return nil, nil, nil, nil, err
			}
			stdout = f

		case arg == "2>":
			if i+1 >= len(args) {
				return nil, nil, nil, nil, fmt.Errorf("syntax error near '2>'")
			}
			i++
			f, err := os.Create(args[i])
			if err != nil {
				return nil, nil, nil, nil, err
			}
			stderr = f

		case arg == "2>&1":
			stderr = stdout

		default:
			newArgs = append(newArgs, arg)
		}
	}

	return newArgs, stdin, stdout, stderr, nil
}

// expandVariables expands environment variables in arguments
func (s *Shell) expandVariables(args []string) []string {
	result := make([]string, len(args))
	for i, arg := range args {
		result[i] = os.Expand(arg, func(key string) string {
			switch key {
			case "?":
				return fmt.Sprintf("%d", s.exitCode)
			case "$":
				return fmt.Sprintf("%d", os.Getpid())
			case "HOME":
				if s.user != nil {
					return s.user.HomeDir
				}
			case "USER":
				if s.user != nil {
					return s.user.Username
				}
			case "SHELL":
				return os.Args[0]
			}
			return os.Getenv(key)
		})
	}
	return result
}

// executePipeline handles piped commands
func (s *Shell) executePipeline(line string) int {
	parts := strings.Split(line, "|")
	if len(parts) < 2 {
		return s.ExecuteCommand(line)
	}

	var cmds []*exec.Cmd
	var argSets [][]string
	background := false

	// Parse all commands
	for i, part := range parts {
		args := s.parseCommand(strings.TrimSpace(part))
		if len(args) == 0 {
			continue
		}

		// Check for background in the last command
		if i == len(parts)-1 && len(args) > 0 && args[len(args)-1] == "&" {
			background = true
			args = args[:len(args)-1]
		}

		if len(args) == 0 {
			continue
		}

		args = s.expandVariables(args)
		argSets = append(argSets, args)
		cmd := exec.Command(args[0], args[1:]...)
		cmds = append(cmds, cmd)
	}

	if len(cmds) == 0 {
		return 0
	}

	// Connect pipes
	for i := 0; i < len(cmds)-1; i++ {
		pipe, err := cmds[i].StdoutPipe()
		if err != nil {
			fmt.Fprintf(os.Stderr, "aush: pipe error: %v\n", err)
			return 1
		}
		cmds[i+1].Stdin = pipe
	}

	// First command reads from stdin
	cmds[0].Stdin = os.Stdin
	// Last command writes to stdout
	cmds[len(cmds)-1].Stdout = os.Stdout
	cmds[len(cmds)-1].Stderr = os.Stderr

	// Start all commands
	for _, cmd := range cmds {
		if err := cmd.Start(); err != nil {
			fmt.Fprintf(os.Stderr, "aush: %v\n", err)
			return 1
		}
	}

	// If background, don't wait, just add to jobs
	if background {
		// We track the last command in the pipeline
		lastCmd := cmds[len(cmds)-1]
		job := &Job{
			ID:       s.nextJobID,
			PID:      lastCmd.Process.Pid,
			Command:  line, // approximate command
			State:    JobRunning,
			Process:  lastCmd.Process,
			DoneChan: make(chan struct{}),
		}
		s.jobs = append(s.jobs, job)
		s.nextJobID++
		fmt.Printf("[%d] %d\n", job.ID, job.PID)

		// Wait in background
		go func() {
			// Wait for all commands in pipeline
			for _, cmd := range cmds {
				cmd.Wait()
			}
			job.State = JobDone
			close(job.DoneChan)
			fmt.Printf("[%d] Done %s\n", job.ID, job.Command)
		}()

		return 0
	}

	// Wait for all commands
	var exitCode int
	for _, cmd := range cmds {
		if err := cmd.Wait(); err != nil {
			if exitErr, ok := err.(*exec.ExitError); ok {
				exitCode = exitErr.ExitCode()
			}
		}
	}

	return exitCode
}

// executeExternal runs an external command
func (s *Shell) executeExternal(args []string, stdin, stdout, stderr *os.File, background bool) int {
	cmd := exec.Command(args[0], args[1:]...)
	cmd.Stdin = stdin
	cmd.Stdout = stdout
	cmd.Stderr = stderr

	if background {
		if err := cmd.Start(); err != nil {
			fmt.Fprintf(os.Stderr, "aush: %s: %v\n", args[0], err)
			return 127
		}

		job := &Job{
			ID:       s.nextJobID,
			PID:      cmd.Process.Pid,
			Command:  strings.Join(args, " "),
			State:    JobRunning,
			Process:  cmd.Process,
			DoneChan: make(chan struct{}),
		}
		s.jobs = append(s.jobs, job)
		s.nextJobID++
		fmt.Printf("[%d] %d\n", job.ID, job.PID)

		go func() {
			cmd.Wait()
			job.State = JobDone
			close(job.DoneChan)
			fmt.Printf("[%d] Done %s\n", job.ID, job.Command)
		}()

		return 0
	}

	if err := cmd.Run(); err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			return exitErr.ExitCode()
		}
		fmt.Fprintf(os.Stderr, "aush: %s: %v\n", args[0], err)
		return 127
	}

	return 0
}

// printPrompt displays the shell prompt
func (s *Shell) printPrompt() {
	// Get current directory
	cwd, err := os.Getwd()
	if err != nil {
		cwd = "?"
	}

	// Shorten home directory to ~
	if s.user != nil && strings.HasPrefix(cwd, s.user.HomeDir) {
		cwd = "~" + cwd[len(s.user.HomeDir):]
	}

	// Prompt symbol based on user
	symbol := "$"
	if s.user != nil && s.user.Uid == "0" {
		symbol = "#"
	}

	// Colors
	userColor := "\033[1;32m"  // green
	hostColor := "\033[1;34m"  // blue
	dirColor := "\033[1;36m"   // cyan
	reset := "\033[0m"

	username := os.Getenv("USER")
	if username == "" {
		if s.user != nil {
			username = s.user.Username
		} else {
			username = "user"
		}
	}

	fmt.Printf("%s%s%s@%s%s%s:%s%s%s%s ", 
		userColor, username, reset,
		hostColor, s.hostname, reset,
		dirColor, cwd, reset,
		symbol)
}

// printWelcome displays a welcome message
func (s *Shell) printWelcome() {
	fmt.Println()
	fmt.Println("  ╔═══════════════════════════════════════╗")
	fmt.Printf("          aush - AULinux Shell v%s     \n", version)
	fmt.Println("  ║     Absolutely Unique Shell           ║")
	fmt.Println("  ╚═══════════════════════════════════════╝")
	fmt.Println()
	fmt.Println("  Type 'help' for available commands.")
	fmt.Println()
}

// setupSignals configures signal handlers
func (s *Shell) setupSignals() {
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		for sig := range sigChan {
			switch sig {
			case syscall.SIGINT:
				fmt.Println()
				s.printPrompt()
			case syscall.SIGTERM:
				s.running = false
			}
		}
	}()
}

// loadHistory loads command history from file
func (s *Shell) loadHistory() {
	if s.user == nil {
		return
	}

	path := filepath.Join(s.user.HomeDir, historyFile)
	f, err := os.Open(path)
	if err != nil {
		return
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		s.history = append(s.history, scanner.Text())
	}
	s.historyPos = len(s.history)
}

// saveHistory saves command history to file
func (s *Shell) saveHistory() {
	if s.user == nil {
		return
	}

	path := filepath.Join(s.user.HomeDir, historyFile)
	f, err := os.Create(path)
	if err != nil {
		return
	}
	defer f.Close()

	// Keep only last maxHistory entries
	start := 0
	if len(s.history) > maxHistory {
		start = len(s.history) - maxHistory
	}

	for i := start; i < len(s.history); i++ {
		fmt.Fprintln(f, s.history[i])
	}
}

// addHistory adds a command to history
func (s *Shell) addHistory(line string) {
	// Don't add duplicates or empty lines
	if line == "" || (len(s.history) > 0 && s.history[len(s.history)-1] == line) {
		return
	}
	s.history = append(s.history, line)
	s.historyPos = len(s.history)
}

// Builtin commands

func builtinCd(s *Shell, args []string) int {
	var target string
	if len(args) == 0 {
		if s.user != nil {
			target = s.user.HomeDir
		} else {
			target = "/"
		}
	} else {
		target = args[0]
	}

	// Handle ~
	if strings.HasPrefix(target, "~") {
		if s.user != nil {
			target = s.user.HomeDir + target[1:]
		}
	}

	if err := os.Chdir(target); err != nil {
		fmt.Fprintf(os.Stderr, "cd: %v\n", err)
		return 1
	}
	return 0
}

func builtinExit(s *Shell, args []string) int {
	s.running = false
	if len(args) > 0 {
		var code int
		fmt.Sscanf(args[0], "%d", &code)
		s.exitCode = code
	}
	return s.exitCode
}

func builtinExport(s *Shell, args []string) int {
	if len(args) == 0 {
		// Print all exported variables
		for _, env := range os.Environ() {
			fmt.Printf("export %s\n", env)
		}
		return 0
	}

	for _, arg := range args {
		parts := strings.SplitN(arg, "=", 2)
		if len(parts) == 2 {
			os.Setenv(parts[0], parts[1])
		} else {
			// Export existing variable
			if val := os.Getenv(parts[0]); val != "" {
				fmt.Printf("export %s=%s\n", parts[0], val)
			}
		}
	}
	return 0
}

func builtinUnset(s *Shell, args []string) int {
	for _, arg := range args {
		os.Unsetenv(arg)
	}
	return 0
}

func builtinPwd(s *Shell, args []string) int {
	cwd, err := os.Getwd()
	if err != nil {
		fmt.Fprintf(os.Stderr, "pwd: %v\n", err)
		return 1
	}
	fmt.Println(cwd)
	return 0
}

func builtinEcho(s *Shell, args []string) int {
	fmt.Println(strings.Join(args, " "))
	return 0
}

func builtinHistory(s *Shell, args []string) int {
	for i, cmd := range s.history {
		fmt.Printf("%5d  %s\n", i+1, cmd)
	}
	return 0
}

func builtinHelp(s *Shell, args []string) int {
	fmt.Println("aush - AULinux Shell")
	fmt.Println()
	fmt.Println("Builtin commands:")
	fmt.Println("  cd [dir]       Change directory")
	fmt.Println("  pwd            Print working directory")
	fmt.Println("  echo [args]    Display text")
	fmt.Println("  export [var]   Set environment variable")
	fmt.Println("  unset var      Unset environment variable")
	fmt.Println("  history        Show command history")
	fmt.Println("  type cmd       Show command type")
	fmt.Println("  help           Show this help")
	fmt.Println("  version        Show version")
	fmt.Println("  exit [code]    Exit the shell")
	fmt.Println()
	fmt.Println("Features:")
	fmt.Println("  - Pipes:        cmd1 | cmd2")
	fmt.Println("  - Redirects:    cmd > file, cmd < file, cmd >> file")
	fmt.Println("  - Variables:    $VAR, $?, $$")
	return 0
}

func builtinVersion(s *Shell, args []string) int {
	fmt.Printf("aush (AULinux Shell) %s\n", version)
	return 0
}

func builtinType(s *Shell, args []string) int {
	if len(args) == 0 {
		return 0
	}

	for _, arg := range args {
		if _, ok := builtins[arg]; ok {
			fmt.Printf("%s is a shell builtin\n", arg)
		} else if path, err := exec.LookPath(arg); err == nil {
			fmt.Printf("%s is %s\n", arg, path)
		} else {
			fmt.Printf("%s: not found\n", arg)
		}
	}
	return 0
}

func printHelp() {
	fmt.Println("Usage: aush [OPTIONS] [COMMAND]")
	fmt.Println()
	fmt.Println("AULinux Shell - Absolutely Unique Shell")
	fmt.Println()
	fmt.Println("Options:")
	fmt.Println("  -c COMMAND    Execute COMMAND and exit")
	fmt.Println("  -l, --login   Start as a login shell")
	fmt.Println("  --version     Show version information")
	fmt.Println("  --help        Show this help message")
}

func (s *Shell) cleanupJobs() {
	var activeJobs []*Job
	for _, job := range s.jobs {
		if job.State != JobDone && job.State != JobTerminated {
			activeJobs = append(activeJobs, job)
		}
	}
	s.jobs = activeJobs
}

func builtinJobs(s *Shell, args []string) int {
	s.cleanupJobs()
	for _, job := range s.jobs {
		fmt.Printf("[%d] %d %s %s\n", job.ID, job.PID, job.State, job.Command)
	}
	return 0
}

func builtinFg(s *Shell, args []string) int {
	if len(args) == 0 {
		// Bring last job to foreground
		if len(s.jobs) == 0 {
			fmt.Fprintln(os.Stderr, "fg: no current job")
			return 1
		}
		// Use last job
		job := s.jobs[len(s.jobs)-1]
		return bringToForeground(s, job)
	}

	// Parse %n or n
	idStr := args[0]
	if strings.HasPrefix(idStr, "%") {
		idStr = idStr[1:]
	}

	var id int
	if _, err := fmt.Sscanf(idStr, "%d", &id); err != nil {
		fmt.Fprintf(os.Stderr, "fg: %s: no such job\n", args[0])
		return 1
	}

	for _, job := range s.jobs {
		if job.ID == id {
			return bringToForeground(s, job)
		}
	}

	fmt.Fprintf(os.Stderr, "fg: %s: no such job\n", args[0])
	return 1
}

func bringToForeground(s *Shell, job *Job) int {
	fmt.Println(job.Command)

	// In a real shell, we would tcsetpgrp here.
	// Here we just wait for it.

    // Check if channel is closed
    select {
    case <-job.DoneChan:
        return 0
    default:
        <-job.DoneChan
        return 0
    }
}

func builtinBg(s *Shell, args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "bg: job ID required")
		return 1
	}

	// Parse %n or n
	idStr := args[0]
	if strings.HasPrefix(idStr, "%") {
		idStr = idStr[1:]
	}

	var id int
	if _, err := fmt.Sscanf(idStr, "%d", &id); err != nil {
		fmt.Fprintf(os.Stderr, "bg: %s: no such job\n", args[0])
		return 1
	}

	for _, job := range s.jobs {
		if job.ID == id {
			// Send SIGCONT
			if err := job.Process.Signal(syscall.SIGCONT); err != nil {
				fmt.Fprintf(os.Stderr, "bg: failed to send SIGCONT: %v\n", err)
				return 1
			}
			job.State = JobRunning
			fmt.Printf("[%d] %s &\n", job.ID, job.Command)
			return 0
		}
	}

	fmt.Fprintf(os.Stderr, "bg: %s: no such job\n", args[0])
	return 1
}
