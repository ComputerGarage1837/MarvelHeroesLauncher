# Marvel Heroes Omega community launcher

A Windows launcher for the community server at myfamilyflix.duckdns.org. Includes a black-and-gold interface, rotating Avengers film artwork, account creation, custom game folders, full installation support, and verified launcher/client updates.

## Players

Download `MarvelHeroesLauncher-Install.zip` from **Releases** and extract it to a writable folder. Existing players can replace launcher files in their current folder: `LauncherSettings.json` and game files are not included or overwritten by the launcher ZIP. Windows and PowerShell 7 are required.

Open `Play.bat`. Select **Locate existing game** and browse to the folder containing your Win64 Marvel Heroes client. Alternatively, select **Choose folder** and **Install Game** once a full-client distribution is published. Game settings contains resolution and window/fullscreen controls. Account creation uses HTTPS; normal login happens in the game. The launcher closes when the game window opens.

Updates are checked on startup. **Install updates** downloads and verifies release packages; the launcher restarts when its own files change. Game files install only while the game is closed. Downloads show bytes and progress and can resume after an interrupted download. Files are checked against SHA-256 hashes. Backups and transaction journals support rollback/recovery after failed installation. Player settings and saved configuration are protected from patches. Changed local game files cause patch installation to stop rather than silently replacing mods.

GitHub releases are the trusted update source. Hashes detect damaged or inconsistent downloads; they are not independent publisher signatures. No GitHub credentials are distributed to players. Full-game downloads are unavailable until the host publishes the client assets.

## Publish launcher updates

1. Edit launcher files and push to this repository.
2. In **Actions → Publish launcher and client updates → Run workflow**, enter a higher version, such as `1.1.1`. Alternatively, push a tag such as `v1.1.1`.
3. The workflow tests the updater, builds ZIPs and a manifest, carries forward existing game packages, and publishes a release. Launchers discover it on their next check.

Do not reuse an existing version for changed files. Keep prereleases out of the stable update feed. Never put account databases, credentials, personal settings, or logs in this repository.

## Prepare a full game download

Run with PowerShell 7 on a machine with the game files:

```powershell
./tools/NewClientDistribution.ps1 -ClientFolder 'D:\Games\Marvel Heroes' -Version 1.52.0.1700
```

The folder must contain the Win64 executable somewhere beneath it. The tool packages game files and default configuration, excludes saved data/logs, and splits the ZIP into 1 GiB release assets. Large individual game files are supported through Zip64. The unsplit ZIP is a local build artifact and must not be uploaded.

Create a prerelease named/tagged `client-patches`. Upload all `client-full-*.zip.partNNN` files and the matching `.package.json` descriptor to that prerelease. Then publish a new launcher version through Actions. The workflow brings those assets into the stable release and enables Install Game. Retain sufficient disk space during packaging and installation; the installer requires temporary staging and rollback space.

## Prepare client patches

Put only changed files in a folder with paths relative to the existing game root. Keep a copy of the **previous** client version for baseline hashes:

```powershell
./tools/NewClientPatch.ps1 -ChangedFiles 'D:\PatchFiles' -PreviousClient 'D:\PreviousClient' -FromVersion 1.52.0.1700 -Version 1.52.0.1701
```

Upload the generated `client-*.zip` and `.package.json` to the `client-patches` prerelease, then publish the next launcher release. Retain every patch in the chain so players can catch up from earlier versions. Patches add/replace files; deletion patches are not supported. The builder excludes configuration files from patches. Full installations can include the original default configuration.

## Local development

```powershell
./tests/Update.Tests.ps1
pwsh -STA -File ./launcher/Play.ps1 -ValidateOnly
./tools/BuildRelease.ps1 -Repository ComputerGarage1837/MarvelHeroesLauncher -Version 1.1.1
```

Launcher settings are per installation. Game patch state is stored in `.mh-client-version.json` inside the selected game folder. `.mh-updates` holds client download cache, staging and rollback copies. `.updates` holds launcher equivalents. These are not part of player save data; character progress remains on the server.

The currently published baseline assumes the compatible 1.52.0.1700 Win64 client. An existing game without patch metadata is treated as this baseline; patches still verify each changed file against its expected baseline hash before replacement.

## Artwork

Unofficial fan project. Avengers: Endgame and Avengers: Infinity War artwork is © Marvel Studios, from the official [Endgame](https://movies.disney.com/avengers-endgame) and [Infinity War](https://movies.disney.com/avengers-infinity-war) film pages. Asset source URLs are recorded in `launcher/Assets/CREDITS.txt`.
