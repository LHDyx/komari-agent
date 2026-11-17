package cmd

import "testing"

func TestSecurityWarningEnabled(t *testing.T) {
	origEnable, origDisable := flags.EnableSecurityWarning, flags.DisableWebSsh
	t.Cleanup(func() {
		flags.EnableSecurityWarning = origEnable
		flags.DisableWebSsh = origDisable
	})

	cases := []struct {
		enable, disableWebSSH, want bool
	}{
		{false, false, false}, // 默认：不显示
		{true, false, true},   // 显式开启
		{true, true, false},   // 关闭远程控制时始终不显示
		{false, true, false},
	}
	for _, c := range cases {
		flags.EnableSecurityWarning = c.enable
		flags.DisableWebSsh = c.disableWebSSH
		if got := securityWarningEnabled(); got != c.want {
			t.Errorf("securityWarningEnabled(enable=%v, disableWebSSH=%v) = %v, want %v",
				c.enable, c.disableWebSSH, got, c.want)
		}
	}
}

func TestSecurityWarningFlagDefaultsOff(t *testing.T) {
	f := RootCmd.PersistentFlags().Lookup("enable-security-warning")
	if f == nil {
		t.Fatal("--enable-security-warning flag is not registered")
	}
	if f.DefValue != "false" {
		t.Fatalf("--enable-security-warning default = %q, want false", f.DefValue)
	}
}
