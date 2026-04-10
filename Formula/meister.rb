class Meister < Formula
  desc "macOS Wartung, Update & Self-Healing"
  homepage "https://github.com/maf4711/homebrew-meister"
  url "https://github.com/maf4711/homebrew-meister/archive/refs/tags/v0.09.tar.gz"
  sha256 "6465846370511345e6bd6028a4b8e3918bcfdb9efcd43192630e33b38149bfb1"
  license "GPL-3.0-only"
  version "0.09"

  depends_on :macos

  def install
    bin.install "meister2026.sh" => "meister"
    (libexec/"tools").install Dir["tools/*"]
    # Symlink tools into bin with meister- prefix
    (libexec/"tools").children.each do |tool|
      bin.install_symlink tool => "meister-#{tool.basename(".sh")}"
    end
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
