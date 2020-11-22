# Publish content into the public site repo
$publishRepo = "../alihacks.github.io"

Write-Host "Deploying to $publishRepo"

hugo -d $publishRepo

$dt = Get-Date -Format "MM/dd/yyyy HH:mm K"
$commitmsg = "Publishing site built at $dt"
Push-Location
Set-Location $publishRepo
git add .
Write-Host $commitmsg
git commit -m "$commitmsg"
git push origin main
Pop-Location