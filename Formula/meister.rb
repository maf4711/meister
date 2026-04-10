class Meister < Formula
  desc "macOS Maintenance, Update & Self-Healing"
  homepage "https://github.com/maf4711/meister"
  url "https://github.com/maf4711/meister/archive/refs/tags/v1.0.tar.gz"
  sha256 "3c0fcd543d4f3bbfc4565530b9ce39fd15a4de75ebdb6250d4a68e988763c7f0"
  license "GPL-3.0-only"
  version "1.0"

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

      Usage:
        meister          Auto-detect maintenance
        meister -a       All modules
        meister -n       Dry-run
        meister -h       Help

      Config: ~/.meister/config
      Logs:   ~/.meister/meister.log
    EOS
  end

  test do
    assert_match "meister", shell_output("#{bin}/meister -h 2>&1", 0)
  end
end
