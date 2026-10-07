param([switch]$CoreOnly)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = Split-Path $PSScriptRoot -Parent
$tools = Join-Path $root '.toolchain'
$build = Join-Path $env:LOCALAPPDATA 'CashDraftAndroid/build'
$env:GRADLE_USER_HOME = Join-Path $env:LOCALAPPDATA 'CashDraftAndroid/gradle'
[System.IO.Directory]::CreateDirectory($tools) | Out-Null

function Get-VerifiedArchive($Url, $Target, $Checksum) {
    if (!(Test-Path $Target)) { Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Target }
    if ($Checksum -and (Get-FileHash $Target -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Checksum.Trim().ToLowerInvariant()) { throw "Archive invalide : $Target" }
}

if (!$env:JAVA_HOME -or !(Test-Path (Join-Path $env:JAVA_HOME 'bin/java.exe'))) {
    $jdk = Get-ChildItem $tools -Directory -Filter 'jdk-*' | Select-Object -First 1
    if (!$jdk) {
        Write-Output 'Telechargement du JDK 17 local...'
        $metadata = Invoke-RestMethod 'https://api.adoptium.net/v3/assets/latest/17/hotspot?architecture=x64&image_type=jdk&os=windows&vendor=eclipse'
        $package = $metadata[0].binary.package
        $archive = Join-Path $tools 'jdk.zip'
        Get-VerifiedArchive $package.link $archive $package.checksum
        Expand-Archive $archive $tools
        $jdk = Get-ChildItem $tools -Directory -Filter 'jdk-*' | Select-Object -First 1
    }
    $env:JAVA_HOME = $jdk.FullName
}
$env:GRADLE_USER_HOME = Join-Path $env:LOCALAPPDATA 'CashDraftAndroid/gradle'
$gradle = Join-Path $tools 'gradle-8.11.1/bin/gradle.bat'
if (!(Test-Path $gradle)) {
    Write-Output 'Telechargement de Gradle 8.11.1...'
    $checksum = Invoke-RestMethod 'https://services.gradle.org/distributions/gradle-8.11.1-bin.zip.sha256'
    $archive = Join-Path $tools 'gradle.zip'
    Get-VerifiedArchive 'https://services.gradle.org/distributions/gradle-8.11.1-bin.zip' $archive $checksum
    Expand-Archive $archive $tools
}
& $gradle -p $root "-PlocalBuildRoot=$build" -PcoreOnly=true :core:test --no-daemon
if ($LASTEXITCODE -ne 0) { throw 'Echec des tests metier.' }
& $gradle -p $root "-PlocalBuildRoot=$build" -PcoreOnly=true wrapper --gradle-version 8.11.1 --no-validate-url --no-daemon
if ($LASTEXITCODE -ne 0) { throw 'Echec de la generation du wrapper.' }
if ($CoreOnly) { return }

$sdk = Join-Path $tools 'android-sdk'
$manager = Join-Path $sdk 'cmdline-tools/latest/bin/sdkmanager.bat'
if (!(Test-Path $manager)) {
    $archive = Join-Path $tools 'android-commandline.zip'
    Get-VerifiedArchive 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip' $archive ''
    $temporary = Join-Path $tools 'android-commandline'
    Expand-Archive $archive $temporary -Force
    [System.IO.Directory]::CreateDirectory((Join-Path $sdk 'cmdline-tools')) | Out-Null
    Move-Item (Join-Path $temporary 'cmdline-tools') (Join-Path $sdk 'cmdline-tools/latest')
}
$env:ANDROID_HOME = $sdk
if (!(Test-Path (Join-Path $sdk 'platforms/android-36/android.jar')) -or !(Test-Path (Join-Path $sdk 'build-tools/35.0.0/aapt2.exe'))) {
    & $manager --sdk_root=$sdk 'platform-tools' 'platforms;android-36' 'build-tools;35.0.0'
    if ($LASTEXITCODE -ne 0) { throw 'Installation du SDK Android interrompue.' }
}
& $gradle -p $root "-PlocalBuildRoot=$build" :app:assembleDebug :app:lintDebug --no-daemon
if ($LASTEXITCODE -ne 0) { throw 'Compilation ou lint Android en echec.' }
$artifacts = Join-Path $root 'artifacts'
[System.IO.Directory]::CreateDirectory($artifacts) | Out-Null
Copy-Item (Join-Path $build 'app/outputs/apk/debug/app-debug.apk') (Join-Path $artifacts 'CashDraft-debug.apk') -Force