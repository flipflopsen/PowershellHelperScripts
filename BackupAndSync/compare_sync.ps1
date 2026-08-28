robocopy 'F:\Backups\SwaggerDriveBackup' 'D:\' `
    /E `
    /L `
    /R:0 `
    /W:0 `
    /COPY:DAT `
    /DCOPY:DT `
    /XJ `
    /FP `
    /BYTES `
    /TEE

$LASTEXITCODE