# typed: false
# frozen_string_literal: true

# Homebrew Formula for meister2026.sh
# macOS Maintenance, Update & Self-Healing Script
#
# Installation:
#   brew tap maf4711/meister
#   brew install meister
#
# Update:
#   brew update && brew upgrade meister

class Meister < Formula
  desc "macOS Maintenance, Update & Self-Healing Script mit Ollama AI"
  homepage "https://github.com/maf4711/meister8"
  version "0.04"
  license "MIT"

  url "https://github.com/maf4711/meister8/archive/refs/tags/v0.04.tar.gz"
  sha256 "21ea512d7617e7da469ce2a888ea043b2122df3f89c94d1a2b105929228c29fa"

  depends_on "jq"
  depends_on "mas"
  depends_on "clamav"
  depends_on "ollama"
  depends_on "terminal-notifier"
  depends_on :macos

  def install
    bin.install "meister2026.sh" => "meister"
  end

  def post_install
    ohai "Konfiguration: ~/.meister/config"
    ohai "Logs:          ~/.meister/meister.log"
    ohai "Starte mit:    meister -h"
  end

  def caveats
    <<~EOS
      meister v#{version} wurde installiert!

      Verwendung:
        meister          Standard-Wartung (Brew, macOS, Ollama AI)
        meister -a       Alle optionalen Module
        meister -n       Dry-Run (nur Vorschau)
        meister -h       Hilfe anzeigen

      Alle Abhaengigkeiten wurden automatisch installiert:
        jq, mas, clamav, ollama, terminal-notifier

      Konfiguration:
        ~/.meister/config              # Einstellungen anpassen
        meister -I                     # LaunchAgent fuer taegl. Ausfuehrung

      Deinstallation:
        brew uninstall meister
        rm -rf ~/.meister              # Config + Logs entfernen (optional)
    EOS
  end

  test do
    assert_match "meister2026", shell_output("#{bin}/meister -h 2>&1", 0)
  end
end
