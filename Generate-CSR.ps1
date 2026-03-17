## PowerShell Script to generate a Certificate Signing Request (CSR) using the SHA256 (SHA-256) signature algorithm and a 2048 bit key size (RSA) via the Cert Request Utility (certreq) ##

<#

.SYNOPSIS
This powershell script can be used to generate a Certificate Signing Request (CSR) using the SHA256 signature algorithm and a 2048 bit key size (RSA). Subject Alternative Names are supported.

.DESCRIPTION
Tested platforms:
- Windows Server 2008R2 with PowerShell 2.0
- Windows 8.1 with PowerShell 4.0
- Windows 10 with PowerShell 5.0

Created By:
Reinout Segers

Resource: https://pscsr256.codeplex.com

Changelog
v1.2 (Corrected)
- Fixed missing quote in INF template
- Fixed crash when no SANs are provided
- Fixed trailing ampersand in SAN list
- Fixed INF file encoding for better compatibility with certreq
- Fixed syntax errors by using here-strings for templates
v1.1
- Added support for Windows Server 2008R2 and PowerShell 2.0
v1.0
- initial version
#>

####################
# Prerequisite check
####################
if (-NOT([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Administrator privileges are required. Please restart this script with elevated rights." -ForegroundColor Red
    Pause
    Throw "Administrator privileges are required. Please restart this script with elevated rights."
}


#######################
# Setting the variables
#######################
$UID = [guid]::NewGuid()
$files = @{}
$files['settings'] = "$($env:TEMP)\$($UID)-settings.inf";
$files['csr'] = "$($env:TEMP)\$($UID)-csr.req"


$request = @{}
$request['SAN'] = @{}
$request['SAN_string'] = "" # Initialize to avoid crash if empty

Write-Host "Provide the Subject details required for the Certificate Signing Request" -ForegroundColor Yellow
$request['CN'] = Read-Host "Common Name (CN)"
$request['O'] = Read-Host "Organisation (O)"
$request['OU'] = Read-Host "Organisational Unit (OU)"
$request['L'] = Read-Host "Locality / City (L)"
$request['S'] = Read-Host "State (S)"
$request['C'] = Read-Host "Country Code (C)"

###########################
# Subject Alternative Names
###########################
$i = 0
Do {
    $i++
    $sanInput = Read-Host "Subject Alternative Name $i (e.g. alt.company.com / leave empty for none)"
    if ($sanInput -ne "") {
        $request['SAN'][$i] = $sanInput
    }
} until ($sanInput -eq "")

#########################
# Create the settings.inf
#########################
# Using a single-quoted here-string for the INF template to avoid any expansion or escaping issues
$settingsInf = @'
[Version]
Signature="$Windows NT$"
[NewRequest]
KeyLength = 2048
Exportable = TRUE
MachineKeySet = TRUE
SMIME = FALSE
RequestType = PKCS10
ProviderName = "Microsoft RSA SChannel Cryptographic Provider"
ProviderType = 12
HashAlgorithm = sha256
;Variables
Subject = "CN={{CN}},OU={{OU}},O={{O}},L={{L}},S={{S}},C={{C}}"
[Extensions]
{{SAN}}


;Certreq info
;http://technet.microsoft.com/en-us/library/dn296456.aspx
;CSR Decoder
;https://certlogik.com/decoder/
;https://ssltools.websecurity.symantec.com/checker/views/csrCheck.jsp
'@

if ($request['SAN'].Count -gt 0) {
    $sanList = @()
    Foreach ($sanItem In $request['SAN'].Values) {
        $sanList += "dns=$sanItem"
    }
    $sanJoined = $sanList -join '&'
    # Use double-quoted here-string for SAN part to allow variable expansion of $sanJoined
    $request['SAN_string'] = @"
2.5.29.17 = "{text}"
_continue_ = "$sanJoined"
"@
}

$settingsInf = $settingsInf.Replace("{{CN}}",$request['CN']).Replace("{{O}}",$request['O']).Replace("{{OU}}",$request['OU']).Replace("{{L}}",$request['L']).Replace("{{S}}",$request['S']).Replace("{{C}}",$request['C']).Replace("{{SAN}}",$request['SAN_string'])

# Save settings to file in temp with ASCII encoding for certreq compatibility
Set-Content -Path $files['settings'] -Value $settingsInf -Encoding Ascii

# Done, we can start with the CSR
Clear-Host

#################################
# CSR TIME
#################################

# Display summary
Write-Host "Certificate information
Common name: $($request['CN'])
Organisation: $($request['O'])
Organisational unit: $($request['OU'])
City: $($request['L'])
State: $($request['S'])
Country: $($request['C'])

Subject alternative name(s): $(if ($request['SAN'].Count -gt 0) { $request['SAN'].Values -join ", " } else { "None" })

Signature algorithm: SHA256
Key algorithm: RSA
Key size: 2048

" -ForegroundColor Yellow

# Run certreq to generate the CSR
certreq -new $files['settings'] $files['csr']

# Output the CSR
if (Test-Path $files['csr']) {
    $CSR = Get-Content $files['csr']
    Write-Output $CSR
    Write-Host "
"

    # Set the Clipboard (Optional)
    Write-Host "Copy CSR to clipboard? (y|n): " -ForegroundColor Yellow -NoNewline
    if ((Read-Host) -ieq "y") {
        $CSR | clip
        Write-Host "Check your ctrl+v
"
    }
} else {
    Write-Host "Error: CSR file was not generated." -ForegroundColor Red
}


########################
# Remove temporary files
########################
$files.Values | ForEach-Object {
    if (Test-Path $_) {
        Remove-Item $_ -ErrorAction SilentlyContinue
    }
}
