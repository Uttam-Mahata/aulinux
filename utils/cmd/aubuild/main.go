package main

import (
	"archive/tar"
	"compress/gzip"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

// Package metadata structure matching pkg-manager/src/model.rs
type Package struct {
	Name          string   `json:"name"`
	Version       string   `json:"version"`
	Description   string   `json:"description,omitempty"`
	Maintainer    string   `json:"maintainer,omitempty"`
	Architecture  string   `json:"architecture,omitempty"`
	InstalledSize uint64   `json:"installed_size"`
	Dependencies  []string `json:"dependencies"`
	OptionalDeps  []string `json:"optional_deps"`
	Conflicts     []string `json:"conflicts"`
	Provides      []string `json:"provides"`
	URL           string   `json:"url,omitempty"`
	License       string   `json:"license,omitempty"`
}

func main() {
	srcDir := flag.String("src", "", "Source directory containing package files")
	outDir := flag.String("out", ".", "Output directory for the package")
	name := flag.String("name", "", "Package name")
	version := flag.String("version", "", "Package version")
	desc := flag.String("desc", "", "Package description")
	arch := flag.String("arch", "x86_64", "Architecture")

	flag.Parse()

	if *srcDir == "" || *name == "" || *version == "" {
		fmt.Println("Usage: aubuild -src <dir> -name <name> -version <version> [options]")
		flag.PrintDefaults()
		os.Exit(1)
	}

	// Calculate installed size
	var size uint64
	err := filepath.Walk(*srcDir, func(_ string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if !info.IsDir() {
			size += uint64(info.Size())
		}
		return nil
	})
	if err != nil {
		fmt.Printf("Error calculating size: %v\n", err)
		os.Exit(1)
	}

	pkg := Package{
		Name:          *name,
		Version:       *version,
		Description:   *desc,
		Architecture:  *arch,
		InstalledSize: size,
	}

	// Create output directory
	if err := os.MkdirAll(*outDir, 0755); err != nil {
		fmt.Printf("Error creating output dir: %v\n", err)
		os.Exit(1)
	}

	// Create JSON metadata file
	jsonName := fmt.Sprintf("%s-%s.json", *name, *version)
	jsonPath := filepath.Join(*outDir, jsonName)
	jsonFile, err := os.Create(jsonPath)
	if err != nil {
		fmt.Printf("Error creating JSON file: %v\n", err)
		os.Exit(1)
	}
	defer jsonFile.Close()

	encoder := json.NewEncoder(jsonFile)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(pkg); err != nil {
		fmt.Printf("Error encoding JSON: %v\n", err)
		os.Exit(1)
	}

	// Create tar.gz archive
	archiveName := fmt.Sprintf("%s-%s.pkg", *name, *version)
	archivePath := filepath.Join(*outDir, archiveName)
	archiveFile, err := os.Create(archivePath)
	if err != nil {
		fmt.Printf("Error creating archive file: %v\n", err)
		os.Exit(1)
	}
	defer archiveFile.Close()

	gw := gzip.NewWriter(archiveFile)
	defer gw.Close()
	tw := tar.NewWriter(gw)
	defer tw.Close()

	// Walk through the source directory and add files to tar
	err = filepath.Walk(*srcDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		// Create header
		header, err := tar.FileInfoHeader(info, info.Name())
		if err != nil {
			return err
		}

		// Update name to be relative to srcDir
		relPath, err := filepath.Rel(*srcDir, path)
		if err != nil {
			return err
		}
		if relPath == "." {
			return nil
		}
		header.Name = relPath

		if err := tw.WriteHeader(header); err != nil {
			return err
		}

		if !info.IsDir() {
			file, err := os.Open(path)
			if err != nil {
				return err
			}
			defer file.Close()
			if _, err := io.Copy(tw, file); err != nil {
				return err
			}
		}
		return nil
	})

	if err != nil {
		fmt.Printf("Error archiving: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Package %s-%s created in %s\n", *name, *version, *outDir)
}
