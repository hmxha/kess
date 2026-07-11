@echo off
setlocal enabledelayedexpansion

REM ================================
REM Flutter Built Web H5 Upload Script
REM Version: 20260701-v3-mime-fixed
REM Upload an already-built Flutter web folder to S3 + CloudFront.
REM No flutter build, no pubspec.yaml required.
REM Explicitly fixes S3 Content-Type for JS/MJS/WASM/CSS/JSON/HTML/SVG/ICO.
REM ================================

set "SCRIPT_VERSION=20260701-v3-mime-fixed"

REM S3 bucket name, without s3://
set "BUCKET_NAME=chess-production-311912733902-ap-southeast-1-an"

REM CloudFront Distribution ID
set "DISTRIBUTION_ID=E2NKDDEEVCX5LT"

REM Optional S3 prefix.
REM Empty means upload to bucket root.
REM Example:
REM set "S3_PREFIX=flutter_h5"
set "S3_PREFIX="

REM Upload folder.
REM Empty means use this BAT file's folder.
REM You can also pass a folder as the first argument:
REM deploy_flutter_h5_upload_only_v3_mime_fixed.bat E:\path\to\flutter_build_web
set "H5_DIR="

REM Cache mode:
REM test = no-cache for HTML/JS/CSS/JSON/WASM and normal static files, safer for staging.
REM prod = long-cache static assets, no-cache entry/config files.
set "CACHE_MODE=test"

REM If using default AWS CLI account, keep empty.
REM Example:
REM set "AWS_PROFILE=aws-prod"
set "AWS_PROFILE="

set "AWS_REGION=ap-southeast-1"

REM CloudFront invalidation paths.
REM 1 = invalidate /* or /prefix/*
REM 0 = invalidate only common Flutter entry/config paths.
set "INVALIDATE_ALL=1"

set "AWS_ARGS=--region %AWS_REGION%"
if not "%AWS_PROFILE%"=="" (
    set "AWS_ARGS=%AWS_ARGS% --profile %AWS_PROFILE%"
)

REM Resolve H5 directory
if not "%~1"=="" (
    set "H5_DIR=%~1"
)

if "%H5_DIR%"=="" (
    pushd "%~dp0"
) else (
    pushd "%H5_DIR%"
)

if errorlevel 1 (
    echo [ERROR] Cannot enter H5 directory: %H5_DIR%
    goto :error_no_pop
)

set "ROOT_DIR=%CD%"
set "ROOT_WITH_SLASH=%CD%\"

if "%S3_PREFIX%"=="" (
    set "S3_URI=s3://%BUCKET_NAME%"
    set "CF_PREFIX="
) else (
    set "S3_URI=s3://%BUCKET_NAME%/%S3_PREFIX%"
    set "CF_PREFIX=/%S3_PREFIX%"
)

echo.
echo ================================
echo Flutter built H5 upload start
echo SCRIPT_VERSION=%SCRIPT_VERSION%
echo ROOT_DIR=%ROOT_DIR%
echo S3_URI=%S3_URI%
echo DISTRIBUTION_ID=%DISTRIBUTION_ID%
echo CACHE_MODE=%CACHE_MODE%
echo ================================
echo.

if not exist "index.html" (
    echo [ERROR] index.html not found in H5 directory.
    echo Put this BAT file in the built Flutter web folder, or pass the folder path as argument.
    echo Example: deploy_flutter_h5_upload_only_v3_mime_fixed.bat E:\New\web\flutter_h5
    popd
    goto :error_no_pop
)

where aws >nul 2>nul
if errorlevel 1 (
    echo [ERROR] aws command not found.
    echo Please install AWS CLI and configure credentials.
    popd
    goto :error_no_pop
)

echo.
echo [1/5] Clean previous wrong uploads...
echo.

aws s3 rm "s3://%BUCKET_NAME%/ROOT_WITH_SLASH" %AWS_ARGS% >nul 2>nul
aws s3 rm "s3://%BUCKET_NAME%/E:/" --recursive %AWS_ARGS% >nul 2>nul

if /I "%CACHE_MODE%"=="test" (
    set "OTHER_CACHE=no-cache,no-store,must-revalidate"
    set "STATIC_CACHE=no-cache,no-store,must-revalidate"
    set "ENTRY_CACHE=no-cache,no-store,must-revalidate"
    goto :upload_common
)

if /I "%CACHE_MODE%"=="prod" (
    set "OTHER_CACHE=public,max-age=31536000,immutable"
    set "STATIC_CACHE=public,max-age=31536000,immutable"
    set "ENTRY_CACHE=no-cache,no-store,must-revalidate"
    goto :upload_common
)

echo [ERROR] Invalid CACHE_MODE: %CACHE_MODE%
echo Use test or prod.
popd
goto :error_no_pop


:upload_common
echo.
echo [2/5] Upload other files...
echo Exclude known web code/config types, then upload them with explicit MIME later.
echo.

aws s3 sync "." "%S3_URI%" ^
  --delete ^
  --exclude ".git/*" ^
  --exclude ".git\*" ^
  --exclude ".svn/*" ^
  --exclude ".svn\*" ^
  --exclude ".idea/*" ^
  --exclude ".idea\*" ^
  --exclude ".vscode/*" ^
  --exclude ".vscode\*" ^
  --exclude "node_modules/*" ^
  --exclude "node_modules\*" ^
  --exclude "*.bat" ^
  --exclude "*.html" ^
  --exclude "*.js" ^
  --exclude "*.mjs" ^
  --exclude "*.wasm" ^
  --exclude "*.json" ^
  --exclude "*.css" ^
  --exclude "*.svg" ^
  --exclude "*.ico" ^
  --exclude "*.map" ^
  --exclude ".last_build_id" ^
  --exclude "NOTICES" ^
  --cache-control "%OTHER_CACHE%" ^
  %AWS_ARGS%

if errorlevel 1 (
    popd
    goto :error_no_pop
)

echo.
echo [3/5] Upload typed files with correct MIME...
echo.

REM HTML/JSON entry and manifests should not be cached.
call :upload_type "*.html" "text/html; charset=utf-8" "%ENTRY_CACHE%"
if errorlevel 1 (
    popd
    goto :error_no_pop
)

call :upload_type "*.json" "application/json; charset=utf-8" "%ENTRY_CACHE%"
if errorlevel 1 (
    popd
    goto :error_no_pop
)

REM JS module MIME must not be text/plain.
REM In test mode these are no-cache; in prod most JS are long-cache, then entry JS are overwritten no-cache in step 4.
call :upload_type "*.js" "application/javascript; charset=utf-8" "%STATIC_CACHE%"
if errorlevel 1 (
    popd
    goto :error_no_pop
)

call :upload_type "*.mjs" "application/javascript; charset=utf-8" "%STATIC_CACHE%"
if errorlevel 1 (
    popd
    goto :error_no_pop
)

call :upload_type "*.css" "text/css; charset=utf-8" "%STATIC_CACHE%"
if errorlevel 1 (
    popd
    goto :error_no_pop
)

call :upload_type "*.wasm" "application/wasm" "%STATIC_CACHE%"
if errorlevel 1 (
    popd
    goto :error_no_pop
)

call :upload_type "*.svg" "image/svg+xml" "%STATIC_CACHE%"
if errorlevel 1 (
    popd
    goto :error_no_pop
)

call :upload_type "*.ico" "image/x-icon" "%STATIC_CACHE%"
if errorlevel 1 (
    popd
    goto :error_no_pop
)

call :upload_type ".last_build_id" "text/plain; charset=utf-8" "%ENTRY_CACHE%"
if errorlevel 1 (
    popd
    goto :error_no_pop
)

call :upload_type "NOTICES" "text/plain; charset=utf-8" "%ENTRY_CACHE%"
if errorlevel 1 (
    popd
    goto :error_no_pop
)

echo.
echo [4/5] Override Flutter entry/config files with no-cache...
echo.

call :upload_no_cache "index.html" "text/html; charset=utf-8"
if errorlevel 1 (
    popd
    goto :error_no_pop
)

call :upload_no_cache "main.dart.js" "application/javascript; charset=utf-8"
if errorlevel 1 (
    popd
    goto :error_no_pop
)

call :upload_no_cache "flutter.js" "application/javascript; charset=utf-8"
if errorlevel 1 (
    popd
    goto :error_no_pop
)

call :upload_no_cache "flutter_bootstrap.js" "application/javascript; charset=utf-8"
if errorlevel 1 (
    popd
    goto :error_no_pop
)

call :upload_no_cache "flutter_service_worker.js" "application/javascript; charset=utf-8"
if errorlevel 1 (
    popd
    goto :error_no_pop
)

call :upload_no_cache "version.json" "application/json; charset=utf-8"
if errorlevel 1 (
    popd
    goto :error_no_pop
)

call :upload_no_cache "manifest.json" "application/json; charset=utf-8"
if errorlevel 1 (
    popd
    goto :error_no_pop
)

call :upload_no_cache "AssetManifest.json" "application/json; charset=utf-8"
if errorlevel 1 (
    popd
    goto :error_no_pop
)

call :upload_no_cache "AssetManifest.bin" "application/octet-stream"
if errorlevel 1 (
    popd
    goto :error_no_pop
)

call :upload_no_cache "FontManifest.json" "application/json; charset=utf-8"
if errorlevel 1 (
    popd
    goto :error_no_pop
)

call :upload_no_cache ".last_build_id" "text/plain; charset=utf-8"
if errorlevel 1 (
    popd
    goto :error_no_pop
)

call :upload_no_cache "NOTICES" "text/plain; charset=utf-8"
if errorlevel 1 (
    popd
    goto :error_no_pop
)

goto :invalidate


:invalidate
echo.
echo [5/5] Create CloudFront invalidation...
echo.

if "%INVALIDATE_ALL%"=="1" (
    if "%CF_PREFIX%"=="" (
        aws cloudfront create-invalidation ^
          --distribution-id "%DISTRIBUTION_ID%" ^
          --paths "/*" ^
          %AWS_ARGS%
    ) else (
        aws cloudfront create-invalidation ^
          --distribution-id "%DISTRIBUTION_ID%" ^
          --paths "%CF_PREFIX%/*" ^
          %AWS_ARGS%
    )
) else (
    if "%CF_PREFIX%"=="" (
        aws cloudfront create-invalidation ^
          --distribution-id "%DISTRIBUTION_ID%" ^
          --paths "/index.html" "/main.dart.js" "/flutter.js" "/flutter_bootstrap.js" "/flutter_service_worker.js" "/version.json" "/manifest.json" ^
          %AWS_ARGS%
    ) else (
        aws cloudfront create-invalidation ^
          --distribution-id "%DISTRIBUTION_ID%" ^
          --paths "%CF_PREFIX%/" "%CF_PREFIX%/index.html" "%CF_PREFIX%/main.dart.js" "%CF_PREFIX%/flutter.js" "%CF_PREFIX%/flutter_bootstrap.js" "%CF_PREFIX%/flutter_service_worker.js" "%CF_PREFIX%/version.json" "%CF_PREFIX%/manifest.json" ^
          %AWS_ARGS%
    )
)

if errorlevel 1 (
    popd
    goto :error_no_pop
)

popd

echo.
echo ================================
echo Deploy success.
echo S3: %S3_URI%
echo CloudFront invalidation submitted.
echo ================================
echo.
pause
exit /b 0


:upload_type
set "PATTERN=%~1"
set "CONTENT_TYPE=%~2"
set "CACHE_CONTROL=%~3"
set "FOUND_ANY=0"

echo.
echo Upload %PATTERN% as %CONTENT_TYPE%

for /f "delims=" %%f in ('where /r "%ROOT_DIR%" "%PATTERN%" 2^>nul') do (
    if exist "%%~ff" (
        set "FULL_PATH=%%~ff"
        call :is_excluded "!FULL_PATH!"
        if "!SKIP_FILE!"=="0" (
            set "REL_PATH=!FULL_PATH:%ROOT_WITH_SLASH%=!"
            set "S3_KEY=!REL_PATH:\=/!"
            set "FOUND_ANY=1"

            echo Upload: !S3_KEY!

            aws s3 cp "%%~ff" "%S3_URI%/!S3_KEY!" ^
              --cache-control "%CACHE_CONTROL%" ^
              --content-type "%CONTENT_TYPE%" ^
              %AWS_ARGS%

            if errorlevel 1 exit /b 1
        )
    )
)

if "%FOUND_ANY%"=="0" (
    echo No %PATTERN% found, skip.
)

exit /b 0


:upload_no_cache
set "FILE_KEY=%~1"
set "CONTENT_TYPE=%~2"

if exist "%FILE_KEY%" (
    echo Upload no-cache: %FILE_KEY%

    aws s3 cp "%FILE_KEY%" "%S3_URI%/%FILE_KEY%" ^
      --cache-control "no-cache,no-store,must-revalidate" ^
      --content-type "%CONTENT_TYPE%" ^
      %AWS_ARGS%

    if errorlevel 1 exit /b 1
) else (
    echo Skip missing: %FILE_KEY%
)

exit /b 0


:is_excluded
set "CHECK_PATH=%~1"
set "SKIP_FILE=0"

echo %CHECK_PATH% | findstr /I /C:"\.git\" /C:"\.svn\" /C:"\.idea\" /C:"\.vscode\" /C:"\node_modules\" >nul
if not errorlevel 1 (
    set "SKIP_FILE=1"
)

echo %CHECK_PATH% | findstr /I /R "\.bat$" >nul
if not errorlevel 1 (
    set "SKIP_FILE=1"
)

exit /b 0


:error_no_pop
echo.
echo ================================
echo Deploy failed.
echo Check error messages above.
echo ================================
pause
exit /b 1
