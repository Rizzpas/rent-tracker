param(
    [string]$FlutterSdk = '',
    [string]$AndroidSdk = '',
    [string]$JavaHome = '',
    [switch]$SkipChecks
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
$cachedTools = Join-Path $env:USERPROFILE '.cache\rent_tracker_tools'
if (!$FlutterSdk) {
    if (Test-Path -LiteralPath "$cachedTools\flutter\bin\flutter.bat") { $FlutterSdk = "$cachedTools\flutter" }
    elseif (Get-Command flutter -ErrorAction SilentlyContinue) { $FlutterSdk = Split-Path -Parent (Split-Path -Parent (Get-Command flutter).Source) }
    else { throw 'Install the Flutter stable SDK, then pass -FlutterSdk <folder>.' }
}
if (!$AndroidSdk) {
    if ($env:ANDROID_HOME) { $AndroidSdk = $env:ANDROID_HOME }
    elseif (Test-Path -LiteralPath "$cachedTools\android-sdk") { $AndroidSdk = "$cachedTools\android-sdk" }
    else { $AndroidSdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
}
if (!$JavaHome) {
    if ($env:JAVA_HOME) { $JavaHome = $env:JAVA_HOME }
    elseif (Test-Path -LiteralPath "$cachedTools\jdk-17.0.20.1+1") { $JavaHome = "$cachedTools\jdk-17.0.20.1+1" }
    else { throw 'Set JAVA_HOME to a JDK 17 or newer installation.' }
}
$env:JAVA_HOME = $JavaHome
$env:ANDROID_HOME = $AndroidSdk
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:PATH = "$FlutterSdk\bin;$JavaHome\bin;$AndroidSdk\platform-tools;$env:PATH"
$flutter = Join-Path $FlutterSdk 'bin\flutter.bat'
& $flutter config --android-sdk $AndroidSdk --jdk-dir $JavaHome
if ($LASTEXITCODE -ne 0) { throw 'Flutter tool configuration failed.' }

# Create a persistent, private local release identity. Keep this folder for updates.
$signingDirectory = Join-Path $env:LOCALAPPDATA 'BahayRent\signing'
$privateProperties = Join-Path $signingDirectory 'key.properties'
if (!(Test-Path -LiteralPath $privateProperties)) {
    New-Item -ItemType Directory -Path $signingDirectory -Force | Out-Null
    $signingKey = Join-Path $signingDirectory 'release.jks'
    if (Test-Path -LiteralPath $signingKey) { throw 'An existing signing key has no properties file. Recover its password before rebuilding.' }
    $randomBytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($randomBytes)
    $rng.Dispose()
    $signingPassword = [Convert]::ToBase64String($randomBytes)
    $env:BAHAY_KEY_PASSWORD = $signingPassword
    try {
        & "$JavaHome\bin\keytool.exe" -genkeypair -v -keystore $signingKey -storetype JKS -alias bahay -keyalg RSA -keysize 3072 -validity 10000 -storepass:env BAHAY_KEY_PASSWORD -keypass:env BAHAY_KEY_PASSWORD -dname 'CN=Bahay Rent, OU=Local application, O=Bahay Rent, C=PH'
        if ($LASTEXITCODE -ne 0) { throw 'Release signing key creation failed.' }
        @("storeFile=$($signingKey.Replace('\','/'))", "storePassword=$signingPassword", 'keyAlias=bahay', "keyPassword=$signingPassword") | Set-Content -LiteralPath $privateProperties -Encoding ASCII
    } finally { Remove-Item Env:\BAHAY_KEY_PASSWORD -ErrorAction SilentlyContinue }
    $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    & icacls.exe $signingDirectory /inheritance:r /grant:r "${currentIdentity}:(OI)(CI)F" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not restrict signing folder permissions.' }
}
Copy-Item -LiteralPath $privateProperties -Destination (Join-Path $projectRoot 'android\key.properties') -Force
& $flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'Package resolution failed.' }
if (!$SkipChecks) {
    & $flutter analyze
    if ($LASTEXITCODE -ne 0) { throw 'Static analysis failed.' }
    & $flutter test
    if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
}
& $flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw 'Android release build failed.' }
New-Item -ItemType Directory -Path (Join-Path $projectRoot 'deliverables') -Force | Out-Null
$apk = Join-Path $projectRoot 'deliverables\Bahay-Rent-1.0.0.apk'
Copy-Item -LiteralPath (Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-release.apk') -Destination $apk -Force
$hash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  Bahay-Rent-1.0.0.apk" | Set-Content -LiteralPath (Join-Path $projectRoot 'deliverables\SHA256SUMS.txt') -Encoding ASCII
Write-Output "APK: $apk"
Write-Output "Keep a private backup of your release signing folder: $signingDirectory"
