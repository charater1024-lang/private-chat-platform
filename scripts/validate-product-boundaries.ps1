[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$workspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Read-WorkspaceFile {
    param([Parameter(Mandatory = $true)] [string] $RelativePath)

    $path = Join-Path $workspaceRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Product-boundary file was not found: $RelativePath"
    }
    return Get-Content -LiteralPath $path -Raw
}

function Assert-Pattern {
    param(
        [Parameter(Mandatory = $true)] [string] $Content,
        [Parameter(Mandatory = $true)] [string] $Pattern,
        [Parameter(Mandatory = $true)] [string] $Message
    )

    if (-not [regex]::IsMatch(
        $Content,
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Multiline
    )) {
        throw "Product boundary failed: $Message"
    }
}

function Assert-NoPattern {
    param(
        [Parameter(Mandatory = $true)] [string] $Content,
        [Parameter(Mandatory = $true)] [string] $Pattern,
        [Parameter(Mandatory = $true)] [string] $Message
    )

    if ([regex]::IsMatch(
        $Content,
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Multiline
    )) {
        throw "Product boundary failed: $Message"
    }
}

function Assert-XmlDocument {
    param(
        [Parameter(Mandatory = $true)] [string] $Content,
        [Parameter(Mandatory = $true)] [string] $Label
    )

    try {
        [void] ([xml] $Content)
    } catch {
        throw "Product boundary failed: $Label is not valid XML. $($_.Exception.Message)"
    }
}

$products = @('everyday_chat', 'secure_collab')
foreach ($product in $products) {
    $androidManifest = Read-WorkspaceFile "apps\$product\android\app\src\main\AndroidManifest.xml"
    Assert-XmlDocument $androidManifest "$product AndroidManifest.xml"
    Assert-Pattern $androidManifest '<uses-permission android:name="android\.permission\.INTERNET"\s*/>' "$product release manifest needs network permission."
    Assert-Pattern $androidManifest 'android:usesCleartextTraffic="false"' "$product must reject cleartext HTTP."
    Assert-Pattern $androidManifest 'android:allowBackup="false"' "$product must not place sensitive app data in Android backups."
    $androidPermissions = @(
        [regex]::Matches($androidManifest, '<uses-permission\s+android:name="([^"]+)"\s*/>') |
            ForEach-Object { $_.Groups[1].Value }
    )
    if ($androidPermissions.Count -ne 1 -or $androidPermissions[0] -cne 'android.permission.INTERNET') {
        throw "Product boundary failed: $product requests an Android permission that has not been reviewed."
    }
    Assert-NoPattern $androidManifest 'android:networkSecurityConfig=' "$product must not add an unaudited Android network-security override."
    Assert-NoPattern $androidManifest 'android:(?:debuggable|testOnly)="true"' "$product release metadata must not enable debugging or test-only mode."

    $androidBuild = Read-WorkspaceFile "apps\$product\android\app\build.gradle.kts"
    Assert-Pattern $androidBuild '^\s*minSdk\s*=\s*24\s*$' "$product must retain the explicit Android compatibility floor."
    Assert-NoPattern $androidBuild 'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)' "$product release builds must never use the debug signing key."
    Assert-Pattern $androidBuild 'signingConfig\s*=\s*signingConfigs\.getByName\("release"\)' "$product release build must use a dedicated release signing configuration."
    $signingPrefix = if ($product -eq 'everyday_chat') { 'EVERYDAY_CHAT' } else { 'SECURE_COLLAB' }
    foreach ($suffix in @('KEYSTORE_PATH', 'KEYSTORE_PASSWORD', 'KEY_ALIAS', 'KEY_PASSWORD')) {
        Assert-Pattern $androidBuild "${signingPrefix}_ANDROID_${suffix}" "$product must keep its product-specific protected Android signing input."
    }
    Assert-NoPattern $androidBuild '^\s*(?:storePassword|keyPassword)\s*=\s*["''][^"'']+["'']\s*$' "$product must not commit Android signing passwords."

    $iosPlist = Read-WorkspaceFile "apps\$product\ios\Runner\Info.plist"
    Assert-XmlDocument $iosPlist "$product iOS Info.plist"
    Assert-Pattern $iosPlist '<key>NSAllowsArbitraryLoads</key>\s*\r?\n\s*<false/>' "$product must not allow arbitrary iOS network loads."
    Assert-NoPattern $iosPlist '<key>NSExceptionAllowsInsecureHTTPLoads</key>\s*\r?\n\s*<true/>' "$product must not allow insecure iOS HTTP exceptions."

    $iosProject = Read-WorkspaceFile "apps\$product\ios\Runner.xcodeproj\project.pbxproj"
    $iosTargets = @(
        [regex]::Matches($iosProject, 'IPHONEOS_DEPLOYMENT_TARGET\s*=\s*([^;]+);') |
            ForEach-Object { $_.Groups[1].Value.Trim() }
    )
    if ($iosTargets.Count -eq 0 -or @($iosTargets | Where-Object { $_ -ne '15.0' }).Count -ne 0) {
        throw "Product boundary failed: $product must keep its reviewed iOS 15.0 compatibility floor."
    }

    $macosProject = Read-WorkspaceFile "apps\$product\macos\Runner.xcodeproj\project.pbxproj"
    $macosTargets = @(
        [regex]::Matches($macosProject, 'MACOSX_DEPLOYMENT_TARGET\s*=\s*([^;]+);') |
            ForEach-Object { $_.Groups[1].Value.Trim() }
    )
    if ($macosTargets.Count -eq 0 -or @($macosTargets | Where-Object { $_ -ne '12.0' }).Count -ne 0) {
        throw "Product boundary failed: $product must keep its reviewed macOS 12.0 compatibility floor."
    }

    foreach ($configuration in @('DebugProfile', 'Release')) {
        $entitlements = Read-WorkspaceFile "apps\$product\macos\Runner\$configuration.entitlements"
        Assert-XmlDocument $entitlements "$product macOS $configuration entitlements"
        Assert-Pattern $entitlements '<key>com\.apple\.security\.app-sandbox</key>\s*\r?\n\s*<true/>' "$product macOS sandbox must remain enabled."
        Assert-Pattern $entitlements '<key>com\.apple\.security\.network\.client</key>\s*\r?\n\s*<true/>' "$product needs only outbound macOS network access."
        Assert-NoPattern $entitlements '<key>com\.apple\.security\.network\.server</key>' "$product client must not accept inbound macOS network connections."
        if ($configuration -eq 'Release') {
            Assert-NoPattern $entitlements '<key>com\.apple\.security\.(?:cs\.allow-jit|cs\.disable-library-validation|get-task-allow)</key>' "$product macOS release must not contain debugging or library-validation bypass entitlements."
        }
    }

    $windowsManifest = Read-WorkspaceFile "apps\$product\windows\runner\runner.exe.manifest"
    Assert-XmlDocument $windowsManifest "$product Windows runner manifest"
    Assert-Pattern $windowsManifest 'supportedOS Id="\{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a\}"' "$product must explicitly declare the Windows 10/11 compatibility family."
    Assert-Pattern $windowsManifest '<requestedExecutionLevel level="asInvoker" uiAccess="false"\s*/>' "$product must not request Windows elevation or UIAccess."
}

$consumerPubspec = Read-WorkspaceFile 'apps\everyday_chat\pubspec.yaml'
$collabPubspec = Read-WorkspaceFile 'apps\secure_collab\pubspec.yaml'
Assert-NoPattern $consumerPubspec '^\s{2}managed_compliance:' 'The privacy client must not depend on managed-recovery code.'
Assert-NoPattern $collabPubspec '^\s{2}managed_compliance:' 'Secure Collab must not depend on escrow or managed-recovery code.'

$consumerLib = Join-Path $workspaceRoot 'apps\everyday_chat\lib'
$consumerSources = (Get-ChildItem -LiteralPath $consumerLib -Recurse -File -Filter '*.dart' |
    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
Assert-NoPattern $consumerSources 'managedRecoverable|ManagedRecovery|managed_compliance|recoveryCapsule|serverRuntimeCanDecrypt\s*=>\s*true' 'Escrow or managed recovery must not leak into the privacy client.'
Assert-Pattern $consumerSources "package:chat_core/privacy_chat_core\.dart" 'The privacy client must use the no-recovery product entrypoint.'
Assert-NoPattern $consumerSources "package:chat_core/(?:chat_core|secure_chat_core)\.dart" 'The privacy client must not import the broad or managed chat_core entrypoint.'
Assert-Pattern $consumerSources "package:chat_core/chat_core_preview\.dart'\s*\r?\n\s+show InMemoryHomeserverRepository;" 'Prototype access to chat_core preview must be narrowed to the in-memory repository.'

$collabLib = Join-Path $workspaceRoot 'apps\secure_collab\lib'
$collabSources = (Get-ChildItem -LiteralPath $collabLib -Recurse -File -Filter '*.dart' |
    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
Assert-Pattern $collabSources "package:chat_core/secure_chat_core\.dart" 'Secure Collab must use its distinct no-escrow product entrypoint.'
Assert-NoPattern $collabSources "package:chat_core/(?:chat_core|privacy_chat_core)\.dart" 'Secure Collab must not import the broad or privacy chat_core entrypoint.'
Assert-Pattern $collabSources "package:chat_core/chat_core_preview\.dart'\s*\r?\n\s+show InMemoryHomeserverRepository;" 'Prototype access to chat_core preview must be narrowed to the in-memory repository.'
Assert-NoPattern $collabSources 'managedRecoverable|ManagedRecovery|managed_compliance|recoveryCapsule|serverRuntimeCanDecrypt\s*=>\s*true' 'Escrow or managed recovery must not leak into Secure Collab.'

$rootPubspec = Read-WorkspaceFile 'pubspec.yaml'
Assert-NoPattern $rootPubspec 'packages/managed_compliance' 'The removed managed-compliance package must not remain in the workspace.'
Assert-Pattern $rootPubspec 'packages/key_transparency' 'The key-transparency package must remain in the workspace.'

$productionRoots = @(
    (Join-Path $workspaceRoot 'apps\everyday_chat\lib'),
    (Join-Path $workspaceRoot 'apps\secure_collab\lib'),
    (Join-Path $workspaceRoot 'packages')
)
$productionDart = foreach ($root in $productionRoots) {
    Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.dart' |
        Where-Object { $_.FullName -notmatch '[\\/]test[\\/]' }
}
$cleartextEndpoints = $productionDart | Select-String -Pattern 'http://'
if ($cleartextEndpoints) {
    $locations = $cleartextEndpoints |
        ForEach-Object { "$($_.Path):$($_.LineNumber)" }
    throw "Product boundary failed: cleartext endpoint literals found: $($locations -join ', ')"
}

Write-Host 'Client product and platform security boundaries passed.' -ForegroundColor Green
