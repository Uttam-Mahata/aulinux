package main

import (
	"fmt"
	"os"
	"syscall"
	"unsafe"
)

// Constants for ioctl
const (
	SIOCGIFFLAGS = 0x8913
	SIOCSIFFLAGS = 0x8914
	IFF_UP       = 0x1
	IFF_RUNNING  = 0x40
)

type ifreq struct {
	Name  [16]byte
	Flags uint16
	_pad  [22]byte
}

func main() {
	if len(os.Args) < 4 {
		printUsage()
		os.Exit(1)
	}

	if os.Args[1] != "link" || os.Args[2] != "set" {
		printUsage()
		os.Exit(1)
	}

	ifName := os.Args[3]
	if len(ifName) >= 16 {
		fmt.Fprintf(os.Stderr, "Interface name too long\n")
		os.Exit(1)
	}

	action := ""
	if len(os.Args) >= 5 {
		action = os.Args[4]
	}

	fd, err := syscall.Socket(syscall.AF_INET, syscall.SOCK_DGRAM, 0)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Socket error: %v\n", err)
		os.Exit(1)
	}
	defer syscall.Close(fd)

	var ifr ifreq
	copy(ifr.Name[:], ifName)

	// Get current flags
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, uintptr(fd), SIOCGIFFLAGS, uintptr(unsafe.Pointer(&ifr)))
	if errno != 0 {
		fmt.Fprintf(os.Stderr, "Ioctl get flags error: %v\n", errno)
		os.Exit(1)
	}

	if action == "up" {
		ifr.Flags |= (IFF_UP | IFF_RUNNING)
	} else if action == "down" {
		ifr.Flags &^= (IFF_UP | IFF_RUNNING)
	} else {
		fmt.Printf("Interface: %s, Flags: %x\n", ifName, ifr.Flags)
		return
	}

	// Set new flags
	_, _, errno = syscall.Syscall(syscall.SYS_IOCTL, uintptr(fd), SIOCSIFFLAGS, uintptr(unsafe.Pointer(&ifr)))
	if errno != 0 {
		fmt.Fprintf(os.Stderr, "Ioctl set flags error: %v\n", errno)
		os.Exit(1)
	}
}

func printUsage() {
	fmt.Printf("Usage: ip link set <dev> [up|down]\n")
}
