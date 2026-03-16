# Verbalize Windows Build Script
param(
    [string]$Configuration = "Release",
    [switch]$Publish,
    [switch]$SingleFile
)

$Version = "1.0.0"
$ProjectPath = "Verbalize\Verbalize.csproj"

Write-Host ""
Write-Host "===================================" -ForegroundColor Cyan
Write-Host " Building Verbalize v$Version" -ForegroundColor Cyan
Write-Host " Configuration: $Configuration" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan

# Restore
Write-Host "`n[1/3] Restoring packages..." -ForegroundColor Yellow
dotnet restore $ProjectPath
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: Restore failed." -ForegroundColor Red; exit 1 }

# Build
Write-Host "`n[2/3] Building..." -ForegroundColor Yellow
dotnet build $ProjectPath -c $Configuration --no-restore
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: Build failed." -ForegroundColor Red; exit 1 }

# Publish
if ($Publish) {
    Write-Host "`n[3/3] Publishing..." -ForegroundColor Yellow

    $publishArgs = @(
        "publish", $ProjectPath,
        "-c", $Configuration,
        "-r", "win-x64",
        "--self-contained", "true",
        "-o", "publish\Verbalize"
    )

    if ($SingleFile) {
        $publishArgs += "-p:PublishSingleFile=true"
        $publishArgs += "-p:IncludeNativeLibrariesForSelfExtract=true"
    }

    & dotnet @publishArgs
    if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: Publish failed." -ForegroundColor Red; exit 1 }

    Write-Host "`nPublished to: publish\Verbalize\" -ForegroundColor Green

    if ($SingleFile) {
        Write-Host "Single-file executable created." -ForegroundColor Green
    }
} else {
    Write-Host "`n[3/3] Skipping publish (use -Publish flag)" -ForegroundColor DarkGray
}

Write-Host "`n===================================" -ForegroundColor Cyan
Write-Host " Build complete!" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Run:     dotnet run --project $ProjectPath -c $Configuration"
Write-Host "Publish: .\build.ps1 -Publish"
Write-Host "Single:  .\build.ps1 -Publish -SingleFile"
