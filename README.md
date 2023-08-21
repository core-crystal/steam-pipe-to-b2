# Steam Pipe To BackBlaze #

This is a small utility script for backing up all versions of a series
of games (or just one game), across multiple branches all at once. This helps
ensure legacy versions of games can always be accessed regardless if they're
pulled from Steam (or shut down from Steam).

This script assumes you have the following utilities installed:

- `DepotDownloader.dll` is in the same working directory, that you can get from [HERE](https://github.com/SteamRE/DepotDownloader).
- `b2`: the backblaze cli installed and available somewhere in your path.
- `PowerShell` to actually run the script itself.

From there you can start fetching games straight away.