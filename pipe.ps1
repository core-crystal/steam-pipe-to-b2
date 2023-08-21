# `Initialize-Variable` will attempt to load a variable from the environment if it is not set in the current context.
function Initialize-Variable([string]$var_name, [bool]$non_empty) {
  if ([string]::IsNullOrWhiteSpace((Get-Variable -Name $var_name -ValueOnly))) {
    Set-Variable -Name "$var_name" -Value [System.Environment]::GetEnvironmentVariable($var_name) -scope global
  }
  if ($non_empty) {
    if ([string]::IsNullOrWhiteSpace((Get-Variable -Name $var_name -ValueOnly))) {
      Write-Host "[$(Get-Date -Format o)] [ERROR] Missing parameter/env-var: [${var_name}], this is required in order to pipe to backblaze!"
      exit 1
    }
  }
}
# `Remove-NewlinesFromVar` removes all newlines of any kind from a variable.
function Remove-NewlinesFromVar([string]$var_name) {
  $__inner_var=(Get-Variable -Name $var_name -ValueOnly)
  $__inner_var=($__inner_var -Replace('\r\n', ''))
  $__inner_var=($__inner_var -Replace('\n', ''))
  Set-Variable -Name "$var_name" -Value $__inner_var -scope global
  $__inner_var=$None
}

# Discord Configuration...
#
# `DISCORD_WEBHOOK`: The webhook to actually end up posting messages too.
# `DISCORD_UPDATE_ROLE_ID`: An optional role id to ping when we send messages in discord.
# `DISCORD_MAINTENANCE_ROLE_ID`: An optional role id to ping when we send messages in discord.
# `DISCORD_SILENCED`: If we want to silence posting to discord for just this single post.
Initialize-Variable "DISCORD_WEBHOOK" $true
Initialize-Variable "DISCORD_UPDATE_ROLE_ID" $false
Initialize-Variable "DISCORD_MAINTENANCE_ROLE_ID" $false
Initialize-Variable "DISCORD_SILENCED" $false
# Steam Configuration...
#
# `STEAM_USERNAME`: The username to authenticate to steam with.
# `STEAM_PASSWORD`: The password to authenticate to steam with.
# `STEAM_BRANCH_NAME`: The branch to fetch steam builds from. (e.g. phasmophobia uses the the name 'public' as the branch name).
# `STEAM_BRANCH_PASSWORD`: The branch password to use when fetching steam builds.
# `STEAM_APP_ID`: The application id to fetch from steam, (e.g. phasmophobia uses the id of 739630 -- you can use steamdb to help find this).
# `STEAM_DEPOT_ID`: The depot id to fetch from steam, (e.g. phasmophobia uses the id of 739631 -- you can use steamdb to help find this).
# `STEAM_OS`: The Operating System to fetch builds from, by default this is windows.
# `STEAM_ARCH`: The architecture to fetch builds from, by default this is 64 bit.
Initialize-Variable "STEAM_USERNAME" $true
Initialize-Variable "STEAM_PASSWORD" $true
Initialize-Variable "STEAM_BRANCH_NAME" $false
Initialize-Variable "STEAM_BRANCH_PASSWORD" $false
Initialize-Variable "STEAM_APP_ID" $true
Initialize-Variable "STEAM_DEPOT_ID" $true
Initialize-Variable "STEAM_OS" $false
Initialize-Variable "STEAM_ARCH" $false
# BackBlaze Configuration...
#
# `B2_BUCKET_NAME`: The name of the bucket to upload to backblaze with.
Initialize-Variable "B2_BUCKET_NAME" $true
# Cleanup any variables/Set Defaults
Remove-NewlinesFromVar "DISCORD_WEBHOOK"
Remove-NewlinesFromVar "DISCORD_UPDATE_ROLE_ID"
Remove-NewlinesFromVar "DISCORD_MAINTENANCE_ROLE_ID"
Remove-NewlinesFromVar "DISCORD_SILENCED"
if ($DISCORD_SILENCED -eq "true") {
  $DISCORD_SILENCED=$true
} else {
  $DISCORD_SILENCED=$false
}
Remove-NewlinesFromVar "STEAM_BRANCH_NAME"
Remove-NewlinesFromVar "STEAM_APP_ID"
Remove-NewlinesFromVar "STEAM_DEPOT_ID"
Remove-NewlinesFromVar "B2_BUCKET_NAME"
if ([string]::IsNullOrWhiteSpace($STEAM_OS)) {
  $STEAM_OS="windows"
}
if ([string]::IsNullOrWhiteSpace($STEAM_ARCH)) {
  $STEAM_ARCH="64"
}

# If the directory for this depot exists, lets remove any pre-existing manifest, and take
# note of any manfiests we know about.
if (Test-Path -Path "./depots/$STEAM_DEPOT_ID") {
  $PreExistingManifestFiles = (Get-ChildItem -Path "./depots/$DEPOT_ID" -Filter manifest_* -Recurse | ForEach-Object{$_.FullName}).Split([Environment]::NewLine)
  foreach ($ManifestFile in $PreExistingManifestFiles) {
    rm $ManifestFile
  }
} else {
  New-Item -Path "./depots/$STEAM_DEPOT_ID" -ItemType Directory -ea 0
  $PreExistingManifestFiles = @()
}

# First we just download the manfiest, and see if it's a manifest we don't have already.
$DepotArgList=(
  "DepotDownloader.dll",
  "-username", "$STEAM_USERNAME", "-password", "$STEAM_PASSWORD", "-remember-password",
  "-app", "$STEAM_APP_ID", "-depot", "$STEAM_DEPOT_ID",
  "-os", "$STEAM_OS", "-osarch", "$STEAM_ARCH"
)
if (![string]::IsNullOrWhiteSpace($STEAM_BRANCH_NAME)) {
  $DepotArgList += ("-beta", "$STEAM_BRANCH_NAME")
}
if (![string]::IsNullOrWhiteSpace($STEAM_BRANCH_PASSWORD)) {
  $DepotArgList += ("-betapassword", "$STEAM_BRANCH_PASSWORD")
}
$manifestOutput = (dotnet @DepotArgList -manifest-only) -join "`n"

$PostExistingManifestFiles = (Get-ChildItem -Path "./depots/$STEAM_DEPOT_ID" -Filter manifest_* -Recurse | ForEach-Object{$_.FullName}).Split([Environment]::NewLine)
if ($PostExistingManifestFiles.Count -eq 0) {
  Write-Host "[$(Get-Date -Format o)] [ERROR] Failed to log into manifest file!"
  New-Item -Name "last-output.txt" -ItemType File -Value "$manifestOutput" -Force

  if (Test-Path "last-was-error.txt" -PathType leaf) {
    Write-Host "[$(Get-Date -Format o)] [INFO] Pinged Discord Already, doing nothing."
  } else {
    if (!$DISCORD_SILENCED) {
      $MsgBody=(@{
        username = "Steam Pipe to B2";
        avatar_url = "https://c.reml.ink/images/icons/steam-pretty-icon.jpg";
        content = "[a:${STEAM_APP_ID},d:${STEAM_DEPOT_ID}] <@&${DISCORD_MAINTENANCE_ROLE_ID}> Failed to fetch the manifest file, this usually means one of the following three things happened:\n  1. Your steam credentials have expired.\n  2. Steam is having issues (this is common on tuesdays when Steam does maintenance).\n  3. The App ID/Depot ID do not exist anymore.\n\nCommand Output:\n\`\`\`\n$manifestOutput\n\`\`\` "
      } | ConvertTo-Json -Depth 5 -EscapeHandling Default)
      Invoke-WebRequest -Uri "$DISCORD_WEBHOOK" -Method POST -Headers @{ "Content-Type" = "application/json" } -Body "$MsgBody"
    }
    New-Item -Name "last-was-error.txt" -ItemType File
  }

  exit
}
if (Test-Path "last-was-error.txt" -PathType leaf) {
  if (!$DISCORD_SILENCED) {
    $MsgBody=(@{
      username = "Steam Pipe to B2";
      avatar_url = "https://c.reml.ink/images/icons/steam-pretty-icon.jpg";
      content = "[a:${STEAM_APP_ID},d:${STEAM_DEPOT_ID}] <@&${DISCORD_MAINTENANCE_ROLE_ID}> Successfully fetched manifest-files after failing, everything is back to normal."
    } | ConvertTo-Json -Depth 5 -EscapeHandling Default)
    Invoke-WebRequest -Uri "$DISCORD_WEBHOOK" -Method POST -Headers @{ "Content-Type" = "application/json" } -Body "$MsgBody"
  }
}
Remove-Item "last-was-error.txt" -ErrorAction Ignore

if (!$PreExistingManifestFiles.contains($PostExistingManifestFiles[0])) {
  if (!$DISCORD_SILENCED) {
    $MsgBody=(@{
      username = "Steam Pipe to B2";
      avatar_url = "https://c.reml.ink/images/icons/steam-pretty-icon.jpg";
      content = "[a:${STEAM_APP_ID},d:${STEAM_DEPOT_ID}] <@&${DISCORD_UPDATE_ROLE_ID}> Foud a new manifest file, \` ${PostExistingManifestFiles[0]} \`, Starting a Download."
    } | ConvertTo-Json -Depth 5 -EscapeHandling Default)
    Invoke-WebRequest -Uri "$DISCORD_WEBHOOK" -Method POST -Headers @{ "Content-Type" = "application/json" } -Body "$MsgBody"
  }

  # This is what actually downloads the game from this specific update.
  dotnet @DepotArgList -validate

  # Now we need to actually upload it if we downloaded anything.
  Set-Location "./depots/$DEPOT_ID"
  $directory_counts=(Get-ChildItem -Directory | Measure-Object)
  Set-Location './../../'
  $PostExistingFolderCount=$directory_counts.Count
  # There will be two folders that exist (the previously downloaded version, and now the new version).
  if ($PostExistingFolderCount -ne 1) {
    # Get the latest directory created since we 'fetched the full game' last.
    #
    # The directory itself will be the build id name.
    $latestDirObj=(Get-ChildItem "./depots/$DEPOT_ID" | Sort-Object CreationTime -Descending | Select-Object -First 1)
    $buildId=$latestDirObj.Name
    # build id prefix defaults to 's' for 'stable'
    $bidPrefix="s"
    if (![string]::IsNullOrWhiteSpace($STEAM_BRANCH_NAME)) {
      $bidPrefix="$STEAM_BRANCH_NAME".SubString(0,1)
    }

    if (!$DISCORD_SILENCED) {
      $MsgBody=(@{
        username = "Steam Pipe to B2";
        avatar_url = "https://c.reml.ink/images/icons/steam-pretty-icon.jpg";
        content = "[a:${STEAM_APP_ID},d:${STEAM_DEPOT_ID}] <@&${DISCORD_UPDATE_ROLE_ID}> Starting Upload of build id: \` ${bidPrefix}${buildID} \`."
      } | ConvertTo-Json -Depth 5 -EscapeHandling Default)
      Invoke-WebRequest -Uri "$DISCORD_WEBHOOK" -Method POST -Headers @{ "Content-Type" = "application/json" } -Body "$MsgBody"
    }
    # Actually perform the synchronization.
    b2 sync "./depots/$DEPOT_ID/${buildId}/" "b2://${B2_BUCKET_NAME}/${bidPrefix}${buildId}/"

    # Remove the older version of the game (so we only have a max of 2 at a time).
    $oldest_dir_name=(Get-ChildItem "./depots/$DEPOT_ID" | Sort-Object CreationTime | Select-Object -First 1)
    rm -r "./depots/${DEPOT_ID}/${oldest_dir_name.Name}"
    
    if (!$DISCORD_SILENCED) {
      $MsgBody=(@{
        username = "Steam Pipe to B2";
        avatar_url = "https://c.reml.ink/images/icons/steam-pretty-icon.jpg";
        content = "[a:${STEAM_APP_ID},d:${STEAM_DEPOT_ID}] <@&${DISCORD_UPDATE_ROLE_ID}> Finished Archival of build id: \` ${bidPrefix}${buildID} \`."
      } | ConvertTo-Json -Depth 5 -EscapeHandling Default)
      Invoke-WebRequest -Uri "$DISCORD_WEBHOOK" -Method POST -Headers @{ "Content-Type" = "application/json" } -Body "$MsgBody"
    }
  }
} else {
  Write-Host "[$(Get-Date -Format o)] [INFO] No New Build."
}