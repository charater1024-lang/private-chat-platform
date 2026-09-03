<#
.SYNOPSIS
Blocks a release while static application identity or signing wiring is incomplete.

.DESCRIPTION
This is a source-level preflight. It intentionally does not claim that any
artifact was built, signed, notarized, installed, or tested on a real device.
Run platform-native build and artifact-signature verification as separate,
mandatory release jobs after this check passes.

.EXAMPLE
./scripts/release-preflight.ps1

.EXAMPLE
./scripts/release-preflight.ps1 -Json

.EXAMPLE
./scripts/release-preflight.ps1 -Product everyday_chat -Platform android
#>
[CmdletBinding()]
param(
    [ValidateSet('all', 'everyday_chat', 'secure_collab')]
    [string]$Product = 'all',

    [ValidateSet('all', 'android', 'windows', 'linux', 'ios', 'macos')]
    [string]$Platform = 'all',

    [switch]$Json,

    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

$workspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$blockers = [System.Collections.Generic.List[object]]::new()

function Add-Blocker {
    param(
        [Parameter(Mandatory = $true)] [string] $Code,
        [Parameter(Mandatory = $true)] [string] $App,
        [Parameter(Mandatory = $true)] [string] $Message
    )

    $blockers.Add([pscustomobject]@{
            code = $Code
            app = $App
            message = $Message
        })
}

function Read-WorkspaceFile {
    param([Parameter(Mandatory = $true)] [string] $RelativePath)

    $path = Join-Path $workspaceRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        Add-Blocker -Code 'metadata-missing' -App 'workspace' -Message "Missing required release metadata: $RelativePath"
        return ''
    }

    return Get-Content -LiteralPath $path -Raw
}

function Test-PlaceholderIdentifier {
    param(
        [Parameter(Mandatory = $true)] [string] $App,
        [Parameter(Mandatory = $true)] [string] $RelativePath,
        [Parameter(Mandatory = $true)] [string] $Content
    )

    if ($Content -match '(?i)\bcom\.example(?:\.|\b)') {
        Add-Blocker -Code 'placeholder-id' -App $App -Message "$RelativePath still contains a com.example identifier. Assign an organization-owned identifier consistently before release."
    }
}

function Test-AndroidSigning {
    param(
        [Parameter(Mandatory = $true)] [string] $App,
        [Parameter(Mandatory = $true)] [string] $Content
    )

    # Comments cannot satisfy signing policy. This intentionally accepts only
    # the reviewed provider-to-signing-property wiring used by both apps.
    $code = [regex]::Replace($Content, '(?s)/\*.*?\*/', '')
    $code = [regex]::Replace($code, '(?m)//.*$', '')

    $releaseStart = [regex]::Match(
        $code,
        '(?m)^\s*(?:release|getByName\(\s*["'']release["'']\s*\))\s*\{'
    )
    $releaseBlock = ''
    if ($releaseStart.Success) {
        $openingBrace = $code.IndexOf('{', $releaseStart.Index)
        $depth = 0
        for ($index = $openingBrace; $index -lt $code.Length; $index++) {
            if ($code[$index] -eq '{') {
                $depth++
            } elseif ($code[$index] -eq '}') {
                $depth--
                if ($depth -eq 0) {
                    $releaseBlock = $code.Substring($openingBrace, $index - $openingBrace + 1)
                    break
                }
            }
        }
    }

    $releaseSigningPattern = '(?s)signingConfig\s*=\s*signingConfigs(?:\.getByName\(\s*["'']release["'']\s*\)|\[\s*["'']release["'']\s*\])'
    $debugSigningPattern = '(?s)signingConfig\s*=\s*signingConfigs(?:\.getByName\(\s*["'']debug["'']\s*\)|\[\s*["'']debug["'']\s*\])'

    if ([string]::IsNullOrWhiteSpace($releaseBlock) -or $releaseBlock -notmatch $releaseSigningPattern) {
        Add-Blocker -Code 'android-signing' -App $App -Message 'Android release does not reference a dedicated release signing configuration. Secret values must be injected from protected CI storage, never committed.'
    }

    if ($releaseBlock -match $debugSigningPattern) {
        Add-Blocker -Code 'android-debug-signing' -App $App -Message 'Android release metadata references the debug signing configuration.'
    }

    $signingPrefix = if ($App -eq 'everyday_chat') { 'EVERYDAY_CHAT' } else { 'SECURE_COLLAB' }
    foreach ($suffix in @('KEYSTORE_PATH', 'KEYSTORE_PASSWORD', 'KEY_ALIAS', 'KEY_PASSWORD')) {
        $variable = "${signingPrefix}_ANDROID_${suffix}"
        $escapedVariable = [regex]::Escape($variable)
        $providerPattern = 'providers\.environmentVariable\(\s*["'']{0}["'']\s*\)' -f $escapedVariable
        if ($code -notmatch $providerPattern) {
            Add-Blocker -Code 'android-signing-input' -App $App -Message "Android release signing must obtain $variable from the protected environment."
        }

        $bindingPattern = switch ($suffix) {
            'KEYSTORE_PATH' { 'file\(\s*releaseSigningInputs\.getValue\(\s*["'']{0}["'']\s*\)\.get\(\)\s*\)' -f $escapedVariable }
            'KEYSTORE_PASSWORD' { 'storePassword\s*=\s*releaseSigningInputs\.getValue\(\s*["'']{0}["'']\s*\)\.get\(\)' -f $escapedVariable }
            'KEY_ALIAS' { 'keyAlias\s*=\s*releaseSigningInputs\.getValue\(\s*["'']{0}["'']\s*\)\.get\(\)' -f $escapedVariable }
            'KEY_PASSWORD' { 'keyPassword\s*=\s*releaseSigningInputs\.getValue\(\s*["'']{0}["'']\s*\)\.get\(\)' -f $escapedVariable }
        }
        if ($code -notmatch "(?s)$bindingPattern") {
            Add-Blocker -Code 'android-signing-binding' -App $App -Message "Android release signing must bind $variable directly to its reviewed signing property."
        }
    }

    foreach ($property in @('storeFile', 'storePassword', 'keyAlias', 'keyPassword')) {
        if ([regex]::Matches($code, "(?m)^\s*${property}\s*=").Count -ne 1) {
            Add-Blocker -Code 'android-signing-binding' -App $App -Message "Android release signing must assign $property exactly once."
        }
    }
    if ($code -notmatch '(?m)^\s*storeFile\s*=\s*keystore\s*$' -or
        $code -notmatch '(?s)require\(\s*keystore\.isFile\s*\)') {
        Add-Blocker -Code 'android-signing-binding' -App $App -Message 'Android release signing must verify and bind the environment-provided keystore file.'
    }

    if ($code -match '(?m)^\s*(?:storePassword|keyPassword)\s*=\s*["''][^"'']+["'']\s*$' -or
        $code -match '(?m)^\s*storeFile\s*=\s*file\(\s*["''][^"'']+["'']\s*\)\s*$') {
        Add-Blocker -Code 'android-signing-secret' -App $App -Message 'Android signing paths or passwords must not be committed as literals.'
    }
}

function Test-AppVersion {
    param(
        [Parameter(Mandatory = $true)] [string] $App,
        [Parameter(Mandatory = $true)] [string] $Content
    )

    $versions = [regex]::Matches($Content, '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$')
    if ($versions.Count -ne 1 -or [int64]$versions[0].Groups[4].Value -lt 1) {
        Add-Blocker -Code 'version-invalid' -App $App -Message 'pubspec.yaml must contain exactly one numeric SemVer and a positive build number.'
    }
}

function Test-AndroidManifest {
    param(
        [Parameter(Mandatory = $true)] [string] $App,
        [Parameter(Mandatory = $true)] [string] $Content
    )

    try {
        [xml] $document = $Content
    } catch {
        Add-Blocker -Code 'android-manifest-invalid' -App $App -Message 'Android release manifest is not valid XML.'
        return
    }

    $androidNamespace = 'http://schemas.android.com/apk/res/android'
    $permissions = @($document.SelectNodes("//*[starts-with(local-name(), 'uses-permission')]"))
    if ($permissions.Count -ne 1 -or
        $permissions[0].LocalName -cne 'uses-permission' -or
        $permissions[0].GetAttribute('name', $androidNamespace) -cne 'android.permission.INTERNET') {
        Add-Blocker -Code 'android-permissions' -App $App -Message 'The current client release manifest may request only android.permission.INTERNET; new permissions require explicit review.'
    }

    $applications = @($document.SelectNodes("//*[local-name()='application']"))
    if ($applications.Count -ne 1) {
        Add-Blocker -Code 'android-application' -App $App -Message 'Android release manifest must contain exactly one application element.'
        return
    }
    $application = $applications[0]
    if ($application.GetAttribute('allowBackup', $androidNamespace) -cne 'false') {
        Add-Blocker -Code 'android-backup' -App $App -Message 'Android backup must remain disabled until encrypted backup semantics are designed.'
    }
    if ($application.GetAttribute('usesCleartextTraffic', $androidNamespace) -cne 'false' -or
        $application.HasAttribute('networkSecurityConfig', $androidNamespace)) {
        Add-Blocker -Code 'android-network-security' -App $App -Message 'Android must reject cleartext traffic and must not add an unaudited network security override.'
    }
    foreach ($attribute in @('debuggable', 'testOnly')) {
        if ($application.HasAttribute($attribute, $androidNamespace) -and
            $application.GetAttribute($attribute, $androidNamespace) -cne 'false') {
            Add-Blocker -Code 'android-debuggable' -App $App -Message "Android release metadata must not enable or defer $attribute to an unresolved value."
        }
    }
}

function Get-PlistValues {
    param(
        [Parameter(Mandatory = $true)] [System.Xml.XmlElement] $Root,
        [Parameter(Mandatory = $true)] [string] $Key,
        [switch] $Recursive
    )

    $keyNodes = if ($Recursive) {
        @($Root.SelectNodes(".//*[local-name()='key']"))
    } else {
        @($Root.SelectNodes("./*[local-name()='key']"))
    }
    $values = [System.Collections.Generic.List[System.Xml.XmlElement]]::new()
    foreach ($keyNode in $keyNodes) {
        if ($keyNode.InnerText -cne $Key) {
            continue
        }
        $valueNode = $keyNode.NextSibling
        while ($null -ne $valueNode -and $valueNode.NodeType -ne [System.Xml.XmlNodeType]::Element) {
            $valueNode = $valueNode.NextSibling
        }
        if ($valueNode -is [System.Xml.XmlElement]) {
            [void] $values.Add($valueNode)
        }
    }
    return $values.ToArray()
}

function Test-AppleNetworkPolicy {
    param(
        [Parameter(Mandatory = $true)] [string] $App,
        [Parameter(Mandatory = $true)] [string] $Content
    )

    try {
        [xml] $document = $Content
    } catch {
        Add-Blocker -Code 'apple-plist-invalid' -App $App -Message 'Apple Info.plist is not valid XML.'
        return
    }

    $rootDictionaries = @($document.SelectNodes("/*[local-name()='plist']/*[local-name()='dict']"))
    if ($rootDictionaries.Count -ne 1) {
        Add-Blocker -Code 'apple-plist-invalid' -App $App -Message 'Apple Info.plist must contain exactly one root dictionary.'
        return
    }
    $atsValues = @(Get-PlistValues -Root $rootDictionaries[0] -Key 'NSAppTransportSecurity')
    if ($atsValues.Count -ne 1 -or $atsValues[0].LocalName -cne 'dict') {
        Add-Blocker -Code 'apple-network-security' -App $App -Message 'iOS must define exactly one NSAppTransportSecurity dictionary.'
        return
    }

    $arbitraryLoads = @(Get-PlistValues -Root $atsValues[0] -Key 'NSAllowsArbitraryLoads')
    if ($arbitraryLoads.Count -ne 1 -or $arbitraryLoads[0].LocalName -cne 'false') {
        Add-Blocker -Code 'apple-network-security' -App $App -Message 'iOS must explicitly reject arbitrary network loads.'
    }

    foreach ($unsafeKey in @(
            'NSAllowsArbitraryLoads',
            'NSAllowsArbitraryLoadsForMedia',
            'NSAllowsArbitraryLoadsInWebContent',
            'NSAllowsLocalNetworking',
            'NSExceptionAllowsInsecureHTTPLoads',
            'NSTemporaryExceptionAllowsInsecureHTTPLoads'
        )) {
        $unsafeValues = @(Get-PlistValues -Root $atsValues[0] -Key $unsafeKey -Recursive)
        if (@($unsafeValues | Where-Object { $_.LocalName -ceq 'true' }).Count -gt 0) {
            Add-Blocker -Code 'apple-network-security' -App $App -Message "Apple transport security must not enable $unsafeKey."
        }
    }
}

function Test-MacosReleaseEntitlements {
    param(
        [Parameter(Mandatory = $true)] [string] $App,
        [Parameter(Mandatory = $true)] [string] $Content
    )

    try {
        [xml] $document = $Content
    } catch {
        Add-Blocker -Code 'macos-entitlements-invalid' -App $App -Message 'macOS release entitlements are not valid XML.'
        return
    }

    $rootDictionaries = @($document.SelectNodes("/*[local-name()='plist']/*[local-name()='dict']"))
    if ($rootDictionaries.Count -ne 1) {
        Add-Blocker -Code 'macos-entitlements-invalid' -App $App -Message 'macOS release entitlements must contain exactly one root dictionary.'
        return
    }
    $sandboxValues = @(Get-PlistValues -Root $rootDictionaries[0] -Key 'com.apple.security.app-sandbox')
    $networkClientValues = @(Get-PlistValues -Root $rootDictionaries[0] -Key 'com.apple.security.network.client')
    if ($sandboxValues.Count -ne 1 -or $sandboxValues[0].LocalName -cne 'true' -or
        $networkClientValues.Count -ne 1 -or $networkClientValues[0].LocalName -cne 'true') {
        Add-Blocker -Code 'macos-entitlements' -App $App -Message 'macOS release must keep the app sandbox and outbound-only network entitlement.'
    }

    foreach ($forbiddenKey in @(
            'com.apple.security.network.server',
            'com.apple.security.cs.allow-jit',
            'com.apple.security.cs.disable-library-validation',
            'com.apple.security.get-task-allow'
        )) {
        if (@(Get-PlistValues -Root $rootDictionaries[0] -Key $forbiddenKey).Count -gt 0) {
            Add-Blocker -Code 'macos-entitlements' -App $App -Message "macOS release contains forbidden entitlement $forbiddenKey."
        }
    }
}

function Test-WindowsManifest {
    param(
        [Parameter(Mandatory = $true)] [string] $App,
        [Parameter(Mandatory = $true)] [string] $Content
    )

    try {
        [xml] $document = $Content
    } catch {
        Add-Blocker -Code 'windows-manifest-invalid' -App $App -Message 'Windows runner manifest is not valid XML.'
        return
    }

    $levels = @($document.SelectNodes("//*[local-name()='requestedExecutionLevel']"))
    if ($levels.Count -ne 1 -or
        $levels[0].GetAttribute('level') -cne 'asInvoker' -or
        $levels[0].GetAttribute('uiAccess') -cne 'false') {
        Add-Blocker -Code 'windows-privilege' -App $App -Message 'Windows release must explicitly run asInvoker without UIAccess.'
    }
}

function Test-AppleSigning {
    param(
        [Parameter(Mandatory = $true)] [string] $App,
        [Parameter(Mandatory = $true)] [string] $Platform,
        [Parameter(Mandatory = $true)] [string] $Content
    )

    $teams = [regex]::Matches($Content, '(?m)DEVELOPMENT_TEAM\s*=\s*([A-Za-z0-9]{10})\s*;?\s*$')
    if ($teams.Count -eq 0) {
        Add-Blocker -Code 'apple-signing' -App $App -Message "$Platform has no concrete 10-character DEVELOPMENT_TEAM value in the materialized release project. Inject and verify the release team on the trusted Apple build runner."
    }

    if ($Content -match '(?m)CODE_SIGNING_ALLOWED\s*=\s*NO\s*;') {
        Add-Blocker -Code 'apple-signing-disabled' -App $App -Message "$Platform disables code signing in project metadata."
    }
}

if ($SelfTest) {
    Test-PlaceholderIdentifier -App 'everyday_chat' -RelativePath 'fixture' -Content 'applicationId = "com.example.fixture"'
    if ($blockers.Count -ne 1 -or $blockers[0].code -ne 'placeholder-id') {
        throw 'Release preflight self-test failed to reject a placeholder identifier.'
    }

    $blockers.Clear()
    $safeAndroid = @'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <uses-permission android:name="android.permission.INTERNET"/>
  <application android:allowBackup="false" android:usesCleartextTraffic="false"/>
</manifest>
'@
    $safeSigning = @'
val releaseSigningInputs = linkedMapOf(
  "EVERYDAY_CHAT_ANDROID_KEYSTORE_PATH" to providers.environmentVariable("EVERYDAY_CHAT_ANDROID_KEYSTORE_PATH"),
  "EVERYDAY_CHAT_ANDROID_KEYSTORE_PASSWORD" to providers.environmentVariable("EVERYDAY_CHAT_ANDROID_KEYSTORE_PASSWORD"),
  "EVERYDAY_CHAT_ANDROID_KEY_ALIAS" to providers.environmentVariable("EVERYDAY_CHAT_ANDROID_KEY_ALIAS"),
  "EVERYDAY_CHAT_ANDROID_KEY_PASSWORD" to providers.environmentVariable("EVERYDAY_CHAT_ANDROID_KEY_PASSWORD"),
)
val keystore = file(releaseSigningInputs.getValue("EVERYDAY_CHAT_ANDROID_KEYSTORE_PATH").get())
require(keystore.isFile)
storeFile = keystore
storePassword = releaseSigningInputs.getValue("EVERYDAY_CHAT_ANDROID_KEYSTORE_PASSWORD").get()
keyAlias = releaseSigningInputs.getValue("EVERYDAY_CHAT_ANDROID_KEY_ALIAS").get()
keyPassword = releaseSigningInputs.getValue("EVERYDAY_CHAT_ANDROID_KEY_PASSWORD").get()
buildTypes {
  release {
    signingConfig = signingConfigs.getByName("release")
  }
}
'@
    Test-AndroidManifest -App 'everyday_chat' -Content $safeAndroid
    Test-AndroidSigning -App 'everyday_chat' -Content $safeSigning
    Test-WindowsManifest -App 'everyday_chat' -Content @'
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security><requestedPrivileges><requestedExecutionLevel level="asInvoker" uiAccess="false"/></requestedPrivileges></security>
  </trustInfo>
</assembly>
'@
    Test-AppleNetworkPolicy -App 'everyday_chat' -Content @'
<plist version="1.0">
  <dict>
    <key>NSAppTransportSecurity</key>
    <dict><key>NSAllowsArbitraryLoads</key><false/></dict>
  </dict>
</plist>
'@
    Test-MacosReleaseEntitlements -App 'everyday_chat' -Content @'
<plist version="1.0">
  <dict>
    <key>com.apple.security.app-sandbox</key><true/>
    <key>com.apple.security.network.client</key><true/>
  </dict>
</plist>
'@
    if ($blockers.Count -ne 0) {
        throw 'Release preflight self-test rejected safe platform-security fixtures.'
    }

    Test-AndroidManifest -App 'everyday_chat' -Content ($safeAndroid -replace 'android.permission.INTERNET', 'android.permission.READ_CONTACTS')
    if (@($blockers | Where-Object { $_.code -eq 'android-permissions' }).Count -ne 1) {
        throw 'Release preflight self-test failed to reject an unreviewed Android permission.'
    }
    Test-AndroidSigning -App 'everyday_chat' -Content ($safeSigning -replace 'getByName\("release"\)', 'getByName("debug")')
    if (@($blockers | Where-Object { $_.code -eq 'android-debug-signing' }).Count -ne 1) {
        throw 'Release preflight self-test failed to reject Android debug signing.'
    }
    Test-AndroidSigning -App 'everyday_chat' -Content ($safeSigning -replace 'storePassword = releaseSigningInputs\.getValue\("EVERYDAY_CHAT_ANDROID_KEYSTORE_PASSWORD"\)\.get\(\)', 'val embedded = "not-a-secret-manager"`nstorePassword = embedded')
    if (@($blockers | Where-Object { $_.code -eq 'android-signing-binding' }).Count -lt 1) {
        throw 'Release preflight self-test failed to reject an indirect Android signing password.'
    }
    Test-AndroidManifest -App 'everyday_chat' -Content ($safeAndroid -replace '</manifest>', '<uses-permission-sdk-23 android:name="android.permission.READ_CONTACTS"/></manifest>')
    if (@($blockers | Where-Object { $_.code -eq 'android-permissions' }).Count -ne 2) {
        throw 'Release preflight self-test failed to reject an alternate Android permission element.'
    }
    Test-AppleNetworkPolicy -App 'everyday_chat' -Content @'
<plist version="1.0">
  <dict>
    <key>NSAppTransportSecurity</key>
    <dict>
      <!-- <key>NSAllowsArbitraryLoads</key><false/> -->
      <key>NSAllowsArbitraryLoads</key><true/>
    </dict>
  </dict>
</plist>
'@
    if (@($blockers | Where-Object { $_.code -eq 'apple-network-security' }).Count -lt 1) {
        throw 'Release preflight self-test failed to ignore a misleading plist comment.'
    }
    Test-WindowsManifest -App 'everyday_chat' -Content @'
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security><requestedPrivileges>
      <requestedExecutionLevel level="asInvoker" uiAccess="false"/>
      <requestedExecutionLevel level="requireAdministrator" uiAccess="false"/>
    </requestedPrivileges></security>
  </trustInfo>
</assembly>
'@
    if (@($blockers | Where-Object { $_.code -eq 'windows-privilege' }).Count -ne 1) {
        throw 'Release preflight self-test failed to reject conflicting Windows privilege declarations.'
    }

    Write-Host 'Release preflight policy self-test passed.' -ForegroundColor Green
    exit 0
}

$apps = @(
    [pscustomobject]@{ Name = 'everyday_chat'; Root = 'apps/everyday_chat' },
    [pscustomobject]@{ Name = 'secure_collab'; Root = 'apps/secure_collab' }
)

if ($Product -ne 'all') {
    $apps = @($apps | Where-Object { $_.Name -eq $Product })
}

$platformIdentifiers = @{
    android = @{}
    windows = @{}
    linux = @{}
    ios = @{}
    macos = @{}
}

foreach ($app in $apps) {
    $pubspecPath = "$($app.Root)/pubspec.yaml"
    Test-AppVersion -App $app.Name -Content (Read-WorkspaceFile -RelativePath $pubspecPath)

    if ($Platform -eq 'all' -or $Platform -eq 'android') {
        $androidPath = "$($app.Root)/android/app/build.gradle.kts"
        $android = Read-WorkspaceFile -RelativePath $androidPath
        Test-PlaceholderIdentifier -App $app.Name -RelativePath $androidPath -Content $android
        Test-AndroidSigning -App $app.Name -Content $android
        Test-AndroidManifest -App $app.Name -Content (Read-WorkspaceFile -RelativePath "$($app.Root)/android/app/src/main/AndroidManifest.xml")

        $namespaceMatch = [regex]::Match($android, '(?m)^\s*namespace\s*=\s*["'']([^"'']+)["'']\s*$')
        $applicationIdMatch = [regex]::Match($android, '(?m)^\s*applicationId\s*=\s*["'']([^"'']+)["'']\s*$')
        $activityRoot = Join-Path $workspaceRoot "$($app.Root)/android/app/src/main/kotlin"
        $activities = if (Test-Path -LiteralPath $activityRoot) {
            @(Get-ChildItem -LiteralPath $activityRoot -Filter 'MainActivity.kt' -File -Recurse)
        } else {
            @()
        }
        if (-not $namespaceMatch.Success -or -not $applicationIdMatch.Success -or $activities.Count -ne 1) {
            Add-Blocker -Code 'android-namespace' -App $app.Name -Message 'Android must have one MainActivity.kt and concrete namespace/applicationId values before release.'
        } else {
            $activity = Get-Content -LiteralPath $activities[0].FullName -Raw
            $packageMatch = [regex]::Match($activity, '(?m)^\s*package\s+([A-Za-z0-9_.]+)\s*$')
            if (-not $packageMatch.Success -or
                $packageMatch.Groups[1].Value -cne $namespaceMatch.Groups[1].Value -or
                $applicationIdMatch.Groups[1].Value -cne $namespaceMatch.Groups[1].Value) {
                Add-Blocker -Code 'android-namespace' -App $app.Name -Message 'MainActivity package, namespace, and applicationId must match exactly.'
            } else {
                $platformIdentifiers['android'][$app.Name] = $applicationIdMatch.Groups[1].Value
            }
        }
    }

    if ($Platform -eq 'all' -or $Platform -eq 'linux') {
        $linuxPath = "$($app.Root)/linux/CMakeLists.txt"
        $linux = Read-WorkspaceFile -RelativePath $linuxPath
        Test-PlaceholderIdentifier -App $app.Name -RelativePath $linuxPath -Content $linux
        $linuxId = [regex]::Match($linux, '(?m)^set\(APPLICATION_ID\s+["'']([^"'']+)["'']\)\s*$')
        if ($linuxId.Success) {
            $platformIdentifiers['linux'][$app.Name] = $linuxId.Groups[1].Value
        } else {
            Add-Blocker -Code 'linux-identity' -App $app.Name -Message 'Linux APPLICATION_ID is missing.'
        }
    }

    if ($Platform -eq 'all' -or $Platform -eq 'windows') {
        $windowsPath = "$($app.Root)/windows/runner/Runner.rc"
        $windows = Read-WorkspaceFile -RelativePath $windowsPath
        Test-PlaceholderIdentifier -App $app.Name -RelativePath $windowsPath -Content $windows
        Test-WindowsManifest -App $app.Name -Content (Read-WorkspaceFile -RelativePath "$($app.Root)/windows/runner/runner.exe.manifest")
        $windowsProject = Read-WorkspaceFile -RelativePath "$($app.Root)/windows/CMakeLists.txt"
        $windowsBinary = [regex]::Match($windowsProject, '(?m)^set\(BINARY_NAME\s+["'']([^"'']+)["'']\)\s*$')
        if ($windowsBinary.Success) {
            $platformIdentifiers['windows'][$app.Name] = $windowsBinary.Groups[1].Value
        } else {
            Add-Blocker -Code 'windows-identity' -App $app.Name -Message 'Windows BINARY_NAME is missing.'
        }
    }

    if ($Platform -eq 'all' -or $Platform -eq 'ios') {
        $iosPath = "$($app.Root)/ios/Runner.xcodeproj/project.pbxproj"
        $iosReleaseConfigPath = "$($app.Root)/ios/Flutter/Release.xcconfig"
        $ios = Read-WorkspaceFile -RelativePath $iosPath
        $iosReleaseConfig = Read-WorkspaceFile -RelativePath $iosReleaseConfigPath
        Test-PlaceholderIdentifier -App $app.Name -RelativePath $iosPath -Content $ios
        Test-AppleSigning -App $app.Name -Platform 'iOS' -Content "$ios`n$iosReleaseConfig"
        Test-AppleNetworkPolicy -App $app.Name -Content (Read-WorkspaceFile -RelativePath "$($app.Root)/ios/Runner/Info.plist")
        $iosIds = @(
            [regex]::Matches($ios, '(?m)PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);') |
                ForEach-Object { $_.Groups[1].Value.Trim() } |
                Where-Object { $_ -notmatch '\.RunnerTests$' } |
                Select-Object -Unique
        )
        if ($iosIds.Count -eq 1) {
            $platformIdentifiers['ios'][$app.Name] = $iosIds[0]
        } else {
            Add-Blocker -Code 'ios-identity' -App $app.Name -Message 'iOS application bundle identifier is missing or inconsistent.'
        }
    }

    if ($Platform -eq 'all' -or $Platform -eq 'macos') {
        $macosProjectPath = "$($app.Root)/macos/Runner.xcodeproj/project.pbxproj"
        $macosConfigPath = "$($app.Root)/macos/Runner/Configs/AppInfo.xcconfig"
        $macosReleaseConfigPath = "$($app.Root)/macos/Runner/Configs/Release.xcconfig"
        $macosProject = Read-WorkspaceFile -RelativePath $macosProjectPath
        $macosConfig = Read-WorkspaceFile -RelativePath $macosConfigPath
        $macosReleaseConfig = Read-WorkspaceFile -RelativePath $macosReleaseConfigPath
        Test-PlaceholderIdentifier -App $app.Name -RelativePath $macosConfigPath -Content $macosConfig
        Test-AppleSigning -App $app.Name -Platform 'macOS' -Content "$macosProject`n$macosReleaseConfig"
        Test-MacosReleaseEntitlements -App $app.Name -Content (Read-WorkspaceFile -RelativePath "$($app.Root)/macos/Runner/Release.entitlements")
        $macosId = [regex]::Match($macosConfig, '(?m)^PRODUCT_BUNDLE_IDENTIFIER\s*=\s*(\S+)\s*$')
        if ($macosId.Success) {
            $platformIdentifiers['macos'][$app.Name] = $macosId.Groups[1].Value
        } else {
            Add-Blocker -Code 'macos-identity' -App $app.Name -Message 'macOS application bundle identifier is missing.'
        }
    }
}

if ($Product -eq 'all') {
    foreach ($platformName in @('android', 'windows', 'linux', 'ios', 'macos')) {
        if (($Platform -eq 'all' -or $Platform -eq $platformName) -and
            $platformIdentifiers[$platformName].Count -eq 2) {
            $unique = @($platformIdentifiers[$platformName].Values | Select-Object -Unique)
            if ($unique.Count -ne 2) {
                Add-Blocker -Code 'identity-collision' -App 'workspace' -Message "Everyday Chat and Secure Collab must have distinct $platformName application identities."
            }
        }
    }
}

$result = [pscustomobject]@{
    status = if ($blockers.Count -eq 0) { 'source_preflight_passed' } else { 'blocked' }
    scope = "Static $Product/$Platform identity, version, platform security, and signing-wiring checks only; no app was built, signed, notarized, installed, or exercised."
    blockers = $blockers
}

if ($Json) {
    $result | ConvertTo-Json -Depth 5
} else {
    Write-Host $result.scope
    if ($blockers.Count -eq 0) {
        Write-Host 'Static release-source preflight passed.' -ForegroundColor Green
    } else {
        foreach ($blocker in $blockers) {
            Write-Host "BLOCKER [$($blocker.code)] $($blocker.app): $($blocker.message)" -ForegroundColor Red
        }
    }
}

if ($blockers.Count -gt 0) {
    exit 1
}

exit 0
