package cmd

import (
	"testing"

	"github.com/komari-monitor/komari-agent/update"
)

// TestDefaultUpdateRepoIsFork 固定默认更新源：自编译版本只跟随本仓库发布的自构建。
func TestDefaultUpdateRepoIsFork(t *testing.T) {
	if defaultUpdateRepo != "LHDyx/komari-agent" {
		t.Fatalf("defaultUpdateRepo = %q, want LHDyx/komari-agent", defaultUpdateRepo)
	}
	if got := RootCmd.PersistentFlags().Lookup("update-repo"); got == nil || got.DefValue != defaultUpdateRepo {
		t.Fatalf("--update-repo default = %v, want %q", got, defaultUpdateRepo)
	}
}

// TestUpdateRepoSwitchesSource 验证切换更新源时的语义：
// 指向自建仓库时打开 allowPrerelease（只跟进 -custom. 自构建），指回官方时关闭。
func TestUpdateRepoSwitchesSource(t *testing.T) {
	t.Cleanup(func() {
		update.Repo = update.UpstreamRepo
		update.AllowPrerelease = false
	})

	if err := update.SetRepo(defaultUpdateRepo); err != nil {
		t.Fatal(err)
	}
	if update.IsUpstreamRepo() {
		t.Fatal("fork repo must not be reported as upstream")
	}

	if err := update.SetRepo(update.UpstreamRepo); err != nil {
		t.Fatal(err)
	}
	if !update.IsUpstreamRepo() {
		t.Fatal("upstream repo should be detected")
	}
}
