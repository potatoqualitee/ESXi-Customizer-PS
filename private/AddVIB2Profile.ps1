function AddVIB2Profile($vib) {
    $ExVersion = ($MyProfile.VibList | Where-Object { $_.Name -eq $vib.Name }).Version

    # Check for vib replacements
    $ExName = ""
    if ($null -eq $ExVersion) {
        foreach ($replaces in $vib.replaces) {
            $ExVib = $MyProfile.VibList | Where-Object { $_.Name -eq $replaces }
            if ($null -eq $ExVib) {
                $ExName = $ExVib.Name + " "
                $ExVersion = $ExVib.Version
                break
            }
        }
    }

    if ($acceptancelevels[$vib.AcceptanceLevel.ToString()] -gt $acceptancelevels[$MyProfile.AcceptanceLevel.ToString()]) {
        Write-Verbose -Message "[New AcceptanceLevel: " + $vib.AcceptanceLevel + "]"
        $MyProfile.AcceptanceLevel = $vib.AcceptanceLevel
    }
    If ($MyProfile.VibList -contains $vib) {
        Write-Verbose -Message "[IGNORED, already added]"
    } else {
        Add-EsxSoftwarePackage -SoftwarePackage $vib -ImageProfile $MyProfile -force -ErrorAction SilentlyContinue | Out-Null
        if ($?) {
            if ($null -eq $ExVersion) {
                Write-Verbose -Message "[OK, added]"
            } else {
                Write-Verbose -Message "[OK, replaced " + $ExName + $ExVersion + "]"
            }
        } else {
            throw "[FAILED, invalid package?]"
        }
    }
}