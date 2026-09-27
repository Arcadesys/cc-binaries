$sourceDir = "turtleos"
$bootFile = "boot.lua"
$outputFile = "install.lua"

$luaContent = "-- TurtleOS Installer`n"
$luaContent += "print('Installing TurtleOS...')`n`n"
$luaContent += "local files = {`n"

# Function to escape Lua string
function Escape-LuaString($str) {
    $str = $str -replace "\\", "\\"
    $str = $str -replace "'", "\'"
    $str = $str -replace "`n", "\n"
    $str = $str -replace "`r", ""
    return "'$str'"
}

# Add boot.lua
if (Test-Path $bootFile) {
    $content = [string](Get-Content $bootFile -Raw)
    # Simple JSON encoding via PowerShell to ensure safe string
    $jsonContent = $content | ConvertTo-Json -Compress
    # Fix PowerShell JSON escaping single quotes and others as \uXXXX which Lua 5.1 doesn't support
    $jsonContent = $jsonContent -replace "\\u0027", "'"
    $jsonContent = $jsonContent -replace "\\u003c", "<"
    $jsonContent = $jsonContent -replace "\\u003e", ">"
    $jsonContent = $jsonContent -replace "\\u0026", "&"
    $luaContent += "    ['$bootFile'] = $jsonContent,`n"
}

# Add turtleos directory
$files = Get-ChildItem -Path $sourceDir -Recurse -File
foreach ($file in $files) {
    $relativePath = $file.FullName.Substring((Get-Item $sourceDir).Parent.FullName.Length + 1).Replace("\", "/")
    $content = [string](Get-Content $file.FullName -Raw)
    $jsonContent = $content | ConvertTo-Json -Compress
    # Fix PowerShell JSON escaping
    $jsonContent = $jsonContent -replace "\\u0027", "'"
    $jsonContent = $jsonContent -replace "\\u003c", "<"
    $jsonContent = $jsonContent -replace "\\u003e", ">"
    $jsonContent = $jsonContent -replace "\\u0026", "&"
    $luaContent += "    ['$relativePath'] = $jsonContent,`n"
}

$luaContent += "}`n`n"

$luaContent += @"
for path, content in pairs(files) do
    print("Writing " .. path)
    local dir = fs.getDir(path)
    if not fs.exists(dir) and dir ~= "" and dir ~= "." then
        fs.makeDir(dir)
    end
    
    local file = fs.open(path, "w")
    file.write(content)
    file.close()
end

if not fs.exists("startup.lua") then
    print("Creating startup.lua...")
    local file = fs.open("startup.lua", "w")
    file.write('shell.run("boot.lua")')
    file.close()
end

print("Installation complete. Rebooting in 3 seconds...")
sleep(3)
os.reboot()
"@

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($outputFile, $luaContent, $utf8NoBom)
Write-Host "Created $outputFile"
