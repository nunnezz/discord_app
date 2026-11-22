netsh http add urlacl url=http://*:8080/ sddl="D:(A;;GX;;;WD)"
Write-Output "urlacl configurado"
