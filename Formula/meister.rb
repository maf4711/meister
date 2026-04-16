class Meister < Formula
  desc "macOS Maintenance, Self-Healing & Dotfiles Sync"
  homepage "https://github.com/maf4711/homebrew-meister"
  url "https://github.com/maf4711/homebrew-meister/archive/refs/tags/v4.0.tar.gz"
  sha256 "4ed32faedbee7b1e29c67ba282b720147d7cb117add34d8857ed43d3161d610c"
  license "GPL-3.0-only"
  version "4.0"

  depends_on :macos

  def install
    bin.install "meister.sh" => "meister"
    (libexec/"tools").install Dir["tools/*"]
    # Symlink tools into bin with meister- prefix
    (libexec/"tools").children.each do |tool|
      bin.install_symlink tool => "meister-#{tool.basename(".sh")}"
    end
  end

  def caveats
    <<~EOS
      meister v#{version} installed!

      Maintenance:
        meister          Auto-detect maintenance
        meister -a       All modules
        meister -h       Help

      Dotfiles Sync:
        meister push     Collect + commit + push
        meister pull     Pull + symlink
        meister setup    First-time clone (auto-detects repo)
        meister bootstrap Full machine setup

      Config: ~/.meister/config
    EOS
  end

  test do
    assert_match "meister", shell_output("#{bin}/meister -h 2>&1", 0)
  end
end
