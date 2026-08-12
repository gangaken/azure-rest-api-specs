Describe "Mark-PackageReleased.ps1" {
    BeforeAll {
        $scriptPath = Join-Path (Join-Path $PSScriptRoot "..") "Mark-PackageReleased.ps1"

        function global:azsdk {
            param (
                [Parameter(ValueFromRemainingArguments = $true)]
                [object[]] $Arguments
            )

            $global:CapturedAzSdkArguments = @($Arguments)
            $global:LASTEXITCODE = $global:AzSdkExitCode
            return $global:AzSdkOutput
        }
    }

    AfterAll {
        Remove-Item Function:\azsdk -ErrorAction SilentlyContinue
        Remove-Variable AzSdkExitCode, AzSdkOutput, CapturedAzSdkArguments -Scope Global -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $global:AzSdkExitCode = 0
        $global:AzSdkOutput = '{"operation_status":"Succeeded","package_name":"azure-test","version":"1.0.0","api_hash":"abc123","api_review_hub":{"succeeded":true,"message":"Package marked released."},"api_view":{"succeeded":true,"message":"Revision marked shipped."}}'
        $global:CapturedAzSdkArguments = @()
    }

    It "passes required and optional release inputs to azsdk" {
        & $scriptPath `
            -Language python `
            -PackageName azure-test `
            -PackageVersion 1.0.0 `
            -ApiHash abc123 `
            -SourceFilePath "path/azure test.zip" `
            -PackageType client `
            -ReviewTokenFileName azure-test_python.json `
            -BuildId 123 `
            -RepoName azure-sdk-for-python `
            -ArtifactName drop `
            -Project public `
            -SourceBranch refs/heads/main

        ($global:CapturedAzSdkArguments -join "|") | Should Be (@(
            "package", "mark-released",
            "--language", "python",
            "--package-name", "azure-test",
            "--package-version", "1.0.0",
            "--api-hash", "abc123",
            "--source-file-path", "path/azure test.zip",
            "--package-type", "client",
            "--artifact-name", "drop",
            "--project", "public",
            "--output", "json",
            "--review-token-file-name", "azure-test_python.json",
            "--build-id", "123",
            "--repo-name", "azure-sdk-for-python",
            "--source-branch", "refs/heads/main"
        ) -join "|")
    }

    It "omits unavailable optional release inputs" {
        & $scriptPath `
            -Language java `
            -PackageName azure-test `
            -PackageVersion 1.0.0 `
            -ApiHash abc123 `
            -SourceFilePath azure-test.jar `
            -PackageType client

        $arguments = $global:CapturedAzSdkArguments -join "|"
        $arguments | Should Not Match "--review-token-file-name"
        $arguments | Should Not Match "--build-id"
        $arguments | Should Not Match "--repo-name"
        $arguments | Should Not Match "--source-branch"
        $arguments | Should Match "--artifact-name\|packages\|--project\|internal"
    }

    It "shows both backend results" {
        $messages = @(& $scriptPath `
            -Language python `
            -PackageName azure-test `
            -PackageVersion 1.0.0 `
            -ApiHash abc123 `
            -SourceFilePath azure-test.zip `
            -PackageType client 6>&1) | ForEach-Object { "$_" }

        [Array]::IndexOf($messages, "API Review Hub") | Should BeLessThan ([Array]::IndexOf($messages, "APIView"))
        ($messages -join [Environment]::NewLine) | Should Match "API Review Hub\r?\n  Status: SUCCEEDED"
        ($messages -join [Environment]::NewLine) | Should Match "APIView\r?\n  Status: SUCCEEDED"
    }

    It "surfaces partial backend failure details from azsdk" {
        $global:AzSdkExitCode = 1
        $global:AzSdkOutput = '{"operation_status":"Failed","api_review_hub":{"succeeded":true,"message":"Package marked released."},"api_view":{"succeeded":false,"message":"APIView failed"},"response_errors":["APIView: APIView failed"]}'

        try {
            & $scriptPath `
                -Language python `
                -PackageName azure-test `
                -PackageVersion 1.0.0 `
                -ApiHash abc123 `
                -SourceFilePath azure-test.zip `
                -PackageType client
        }
        catch {
            $_.Exception.Message | Should Match "APIView: APIView failed"
        }
    }

    It "includes raw output when azsdk returns malformed output" {
        $global:AzSdkExitCode = 1
        $global:AzSdkOutput = "distinct raw command output"

        try {
            & $scriptPath `
                -Language python `
                -PackageName azure-test `
                -PackageVersion 1.0.0 `
                -ApiHash abc123 `
                -SourceFilePath azure-test.zip `
                -PackageType client
        }
        catch {
            $_.Exception.Message | Should Match "distinct raw command output"
        }
    }

    It "fails when the response contract omits a backend result" {
        $global:AzSdkOutput = '{"operation_status":"Succeeded","api_review_hub":{"succeeded":true,"message":"Package marked released."}}'

        { & $scriptPath `
            -Language python `
            -PackageName azure-test `
            -PackageVersion 1.0.0 `
            -ApiHash abc123 `
            -SourceFilePath azure-test.zip `
            -PackageType client } | Should Throw
    }
}
