package main

import (
	"reflect"
	"testing"
)

func TestParseArgs(t *testing.T) {
	opts, err := parseArgs([]string{
		"--extract", "/tmp/bundle", "--dry-run", "--keep-temp",
		"-e", "https://panel.example.com", "-t", "TOKEN", "-i", "10",
	})
	if err != nil {
		t.Fatal(err)
	}
	if opts.extract != "/tmp/bundle" || !opts.dryRun || !opts.keepTemp {
		t.Fatalf("unexpected installer options: %+v", opts)
	}
	want := []string{"-e", "https://panel.example.com", "-t", "TOKEN", "-i", "10"}
	if !reflect.DeepEqual(opts.agentArgs, want) {
		t.Fatalf("agentArgs = %#v, want %#v", opts.agentArgs, want)
	}
}

func TestParseArgsExtractEquals(t *testing.T) {
	opts, err := parseArgs([]string{"--extract=/tmp/x", "--version"})
	if err != nil {
		t.Fatal(err)
	}
	if opts.extract != "/tmp/x" || !opts.showVersion {
		t.Fatalf("unexpected options: %+v", opts)
	}
	if len(opts.agentArgs) != 0 {
		t.Fatalf("unexpected passthrough args: %#v", opts.agentArgs)
	}
}

func TestParseArgsMissingExtractValue(t *testing.T) {
	if _, err := parseArgs([]string{"--extract"}); err == nil {
		t.Fatal("expected error for --extract without value")
	}
}
