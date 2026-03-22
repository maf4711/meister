class Meister < Formula
  desc "macOS Wartung, Update & Self-Healing"
  homepage "https://github.com/maf4711/meister"
  url "https://github.com/maf4711/meister/archive/refs/tags/v0.09.tar.gz"
  sha256 "f9850dcec02765c546ef9a6988d209264b6b32a13af7046a3dac98f97b179e9c"
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
