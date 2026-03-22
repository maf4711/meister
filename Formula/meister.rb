class Meister < Formula
  desc "macOS Wartung, Update & Self-Healing"
  homepage "https://github.com/maf4711/meister"
  url "https://github.com/maf4711/meister/archive/refs/tags/v0.09.tar.gz"
  sha256 "3997a147ef6cc78deb2951888ed6a8ea144411c9fad6c53015c3579d3038e897"
  license "MIT"
  version "0.09"

  depends_on :macos

  def install
    bin.install "meister2026.sh" => "meister"
  end

  def caveats
    <<~EOS
      meister v#{version} wurde installiert!

      Verwendung:
        meister          Auto-Detect Wartung
        meister -a       Alle Module
        meister -n       Dry-Run
        meister -h       Hilfe

      Konfiguration: ~/.meister/config
      Logs: ~/.meister/meister.log
    EOS
  end

  test do
    assert_match "meister2026", shell_output("#{bin}/meister -h 2>&1", 0)
  end
end
