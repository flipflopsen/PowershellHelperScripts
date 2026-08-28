robocopy 'F:\Backups\SwaggerDriveBackup' 'D:\' `
    /E `
    /MT:64 `
    /J `
    /R:1 `
    /W:1 `
    /COPY:DAT `
    /DCOPY:DT `
    /XJ `
    /TEE

$LASTEXITCODE