cask "puzzles" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/nickvigilante/puzzles/releases/download/v#{version}/Puzzles-#{version}.dmg"
  name "Simon Tatham's Puzzle Collection"
  desc "Collection of small one-player logic puzzles"
  homepage "https://www.chiark.greenend.org.uk/~sgtatham/puzzles/"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "Puzzles.app"

  zap trash: [
    "~/Library/Preferences/uk.org.greenend.chiark.sgtatham.puzzles.plist",
    "~/Library/Saved Application State/uk.org.greenend.chiark.sgtatham.puzzles.savedState",
  ]
end
