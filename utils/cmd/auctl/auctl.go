// Package auctl implements the AULinux service control CLI.
// It connects to /run/auinit.sock and sends commands to au-init.
//
// Usage:
//   auctl status [service]    - show service status
//   auctl start <service>     - start a service
//   auctl stop <service>      - stop a service
//   auctl restart <service>   - restart a service
//   auctl list                - list all services
//   auctl shutdown            - graceful system shutdown
//   auctl reboot              - reboot the system
package auctl

import (
	"bufio"
	"fmt"
	"net"
	"os"
	"strings"
	"time"
)

const controlSock = "/run/auinit.sock"

func Run(args []string) {
	if len(args) == 0 || args[0] == "--help" || args[0] == "-h" {
		printHelp()
		os.Exit(0)
	}
	if args[0] == "--version" {
		fmt.Println("auctl 2.0.0 — AULinux Service Control")
		os.Exit(0)
	}

	verb := strings.ToUpper(args[0])
	var cmd string

	switch verb {
	case "STATUS", "LIST":
		if len(args) > 1 {
			cmd = "STATUS " + args[1]
		} else {
			cmd = "STATUS"
		}
	case "START", "STOP", "RESTART":
		if len(args) < 2 {
			fmt.Fprintf(os.Stderr, "auctl: %s requires a service name\n", args[0])
			os.Exit(1)
		}
		cmd = verb + " " + args[1]
	case "SHUTDOWN", "REBOOT":
		cmd = verb
	default:
		fmt.Fprintf(os.Stderr, "auctl: unknown command '%s'\n", args[0])
		fmt.Fprintf(os.Stderr, "Run 'auctl --help' for usage.\n")
		os.Exit(1)
	}

	// Connect to au-init control socket
	conn, err := net.DialTimeout("unix", controlSock, 3*time.Second)
	if err != nil {
		fmt.Fprintf(os.Stderr, "auctl: cannot connect to au-init (%s): %v\n", controlSock, err)
		fmt.Fprintf(os.Stderr, "       Is au-init running as PID 1?\n")
		os.Exit(1)
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(10 * time.Second))

	// Send command
	fmt.Fprintf(conn, "%s\n", cmd)

	// Print response
	scanner := bufio.NewScanner(conn)
	exitCode := 0
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "ERR ") {
			fmt.Fprintln(os.Stderr, strings.TrimPrefix(line, "ERR "))
			exitCode = 1
		} else if strings.HasPrefix(line, "OK ") {
			fmt.Println(strings.TrimPrefix(line, "OK "))
		} else {
			fmt.Println(line)
		}
	}
	os.Exit(exitCode)
}

func printHelp() {
	fmt.Print(`auctl — AULinux Service Control (au-init v2.0)

Usage:
  auctl <command> [service]

Commands:
  status [service]   Show status of all services or a specific one
  list               Alias for 'status'
  start  <service>   Start a service
  stop   <service>   Stop a service (graceful: ExecStop → SIGTERM → SIGKILL)
  restart <service>  Restart a service
  shutdown           Gracefully shut down the system
  reboot             Reboot the system

Examples:
  auctl status               # List all services
  auctl status dhcpcd        # Show dhcpcd status
  auctl start sshd           # Start sshd
  auctl restart dhcpcd       # Restart DHCP client
  auctl stop myapp           # Stop myapp
  auctl shutdown             # Shut down the system

Control socket: /run/auinit.sock
`)
}
