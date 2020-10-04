function Initialize-TenServer {
    <#
    .SYNOPSIS


    .DESCRIPTION

    .PARAMETER OfflineBundle
        Use the VMware Offline bundle zip as input instead of the Online depot

    .PARAMETER Update
        Used only with OfflineBundle, this parameter updates a local bundle with an ESXi patch from the VMware Online depot.

        Combine this with the matching ESXi version.

    .PARAMETER PatchBundle
        Use an Offline patch bundle zip instead of the Online depot when using -Update.

    .PARAMETER PackagePath
        The path to directories of Offline bundles and/or VIB files that are to be added to the ISO.
        NOTEEE: Load too

    .PARAMETER OutBundle
        Output an Offline bundle instead of an installation ISO

    .PARAMETER Path
        Directory to store the customized ISO or Offline bundle.

        The default is the script directory.

    .PARAMETER Depot
        Connect additional Online depots by URL or local Offline bundles by file name.

    .PARAMETER RemovePackage
        Remove named VIB packages from the custom ImageProfile.

    .PARAMETER ImageProfile
        Select an ImageProfile from the current list.

        (default = auto-select latest available standard profile)

    .PARAMETER Version
        Use only ESXi 7.0/6.7/6.5/6.0/5.5/5.1/5.0 ImageProfiles as input, ignore other versions

    .PARAMETER ImageProfileName
        The name of the Image Profile

    .PARAMETER ImageProfileDescription
        The description of the Image Profile

    .PARAMETER ImageProfileVendor
        The vendor of the Image Profile. The default is derived from the cloned input ImageProfile.

    # TEST WAS NOT USED

    .LINK
        https://ESXi-Customizer-PS.v-front.de

    .EXAMPLE
        PS> example
    #>
    [CmdletBinding()]
    param
    (
        [Alias('iZip')]
        [string]$OfflineBundle,
        [Alias('pkgDir')]
        [string[]]$PackagePath,
        [Alias('outDir')]
        [string]$Path = $(Split-Path $MyInvocation.MyCommand.Path),
        [Alias('ipname')]
        [string]$ImageProfileName,
        [Alias('ipvendor')]
        [string]$ImageProfileVendor,
        [Alias('ipdesc')]
        [string]$ImageProfileDescription,
        [Alias('vft')]
        [switch]$UseVFrontOnlineDepot,
        [Alias('dpt')]
        [string[]]$Depot,
        [Alias('load')]
        [string[]]$load,
        [Alias('remove')]
        [string[]]$RemovePackage,
        [Alias('sip')]
        [switch]$ImageProfile,
        [Alias('nsc')]
        [switch]$NoSignatureCheck,
        [Alias('ozip')]
        [switch]$OutBundle,
        [ValidateSet("50", "51", "55", "60", "65", "67", "70")]
        [string]$Version,
        [switch]$Update,
        [ValidateSet("https://vibsdepot.v-front.de/", "https://hostupdate.vmware.com/software/VUM/PRODUCTION/main/vmw-depot-index.xml")]
        [Alias('vmwdepotURL')]
        [string]$Uri = "https://hostupdate.vmware.com/software/VUM/PRODUCTION/main/vmw-depot-index.xml",
        [Alias('pzip')]
        [string]$PatchBundle
    )

    process {
        # Online depot URLs
        if ($Uri -eq "https://vibsdepot.v-front.de/") {
            $UseVFrontOnlineDepotdepotURL = $true
        }

        # Function to test if entered string is numeric
        function isNumeric ($x) {
            $x2 = 0
            $isNum = [System.Int32]::TryParse($x, [ref]$x2)
            return $isNum
        }

        # Parameter sanity check

        if ($Update -and -not $OfflineBundle) {
            throw "FATAL ERROR: -update requires -izip!"
        }

        if ($Update) {
            # Try to add Offline bundle specified by -izip
            Write-Verbose -Message "Adding Base Offline bundle $OfflineBundle (to be updated)..."
            try {
                $upddepot = Add-EsxSoftwaredepot $OfflineBundle -ErrorAction Stop
                Write-Verbose -Message "[OK]"
            } catch {
                throw "Cannot add Base Offline bundle!"
            }

            try {
                $CloneIP = Get-EsxImageProfile -Softwaredepot $upddepot -ErrorAction Stop
            } catch {
                throw "No ImageProfiles found in Base Offline bundle!"
            }

            if ($CloneIP -is [system.array]) {
                # Input Offline bundle includes multiple ImageProfiles. Pick only the latest standard profile:
                Write-Verbose -Message "Warning: Input Offline Bundle contains multiple ImageProfiles. Will pick the latest standard profile!"
                $CloneIP = @( $CloneIP | Sort-Object -Descending -Property @{Expression = { $_.Name.Substring(0, 10) } }, @{Expression = { $_.CreationTime.Date } }, Name )[0]
            }
        }

        if ($Update -and -not $PatchBundle) {
            $vmwdepotURL = $PatchBundle
        }

        if (($OfflineBundle -eq "") -or $Update) {
            # Connect the VMware ESXi base depot
            Write-Verbose -Message "Connecting the VMware ESXi Software depot ..."
            if ($basedepot = Add-EsxSoftwaredepot $vmwdepotURL) {
                Write-Verbose -Message "[OK]"
            } else {
                write-host -F Red "FATAL ERROR: Cannot add VMware ESXi Online depot. Please check your Internet connectivity and/or proxy settings!`n"
                exit
            }
        } else {
            # Try to add Offline bundle specified by -izip
            Write-Verbose -Message "Adding base Offline bundle $OfflineBundle ..."
            if ($basedepot = Add-EsxSoftwaredepot $OfflineBundle) {
                Write-Verbose -Message "[OK]"
            } else {
                write-host -F Red "FATAL ERROR: Cannot add VMware base Offline bundle!`n"
                exit
            }
        }

        if ($UseVFrontOnlineDepot) {
            # Connect the V-Front Online depot
            Write-Verbose -Message "Connecting the V-Front Online depot ..."
            if ($UseVFrontOnlineDepotdepot = Add-EsxSoftwaredepot $UseVFrontOnlineDepotdepotURL) {
                Write-Verbose -Message "[OK]"
            } else {
                write-host -F Red "FATAL ERROR: Cannot add the V-Front Online depot. Please check your internet connectivity and/or proxy settings!`n"
                exit
            }
        }

        if ($Depot -ne @()) {
            # Connect additional depots (Online depot or Offline bundle)
            $AddDpt = @()
            for ($i = 0; $i -lt $Depot.Length; $i++ ) {
                Write-Verbose -Message ("Connecting additional depot " + $Depot[$i] + " ...")
                if ($AddDpt += Add-EsxSoftwaredepot $Depot[$i]) {
                    Write-Verbose -Message "[OK]"
                } else {
                    write-host -F Red "FATAL ERROR: Cannot add Online depot or Offline bundle. In case of Online depot check your Internet"
                    write-host -F Red "connectivity and/or proxy settings! In case of Offline bundle check file name, format and permissions!`n"
                    exit
                }
            }

        }

        Write-Verbose -Message "Getting ImageProfiles, please wait ..."
        $iplist = @()
        if ($OfflineBundle -and !($Update)) {
            Get-EsxImageProfile -Softwaredepot $basedepot | foreach { $iplist += $_ }
        } else {
            if ($v70) {
                Get-EsxImageProfile "ESXi-7.0*" -Softwaredepot $basedepot | foreach { $iplist += $_ }
            } else {
                if ($v67) {
                    Get-EsxImageProfile "ESXi-6.7*" -Softwaredepot $basedepot | foreach { $iplist += $_ }
                } else {
                    if ($v65) {
                        Get-EsxImageProfile "ESXi-6.5*" -Softwaredepot $basedepot | foreach { $iplist += $_ }
                    } else {
                        if ($v60) {
                            Get-EsxImageProfile "ESXi-6.0*" -Softwaredepot $basedepot | foreach { $iplist += $_ }
                        } else {
                            if ($v55) {
                                Get-EsxImageProfile "ESXi-5.5*" -Softwaredepot $basedepot | foreach { $iplist += $_ }
                            } else {
                                if ($v51) {
                                    Get-EsxImageProfile "ESXi-5.1*" -Softwaredepot $basedepot | foreach { $iplist += $_ }
                                } else {
                                    if ($v50) {
                                        Get-EsxImageProfile "ESXi-5.0*" -Softwaredepot $basedepot | foreach { $iplist += $_ }
                                    } else {
                                        # Workaround for http://kb.vmware.com/kb/2089217
                                        Get-EsxImageProfile "ESXi-5.0*" -Softwaredepot $basedepot | foreach { $iplist += $_ }
                                        Get-EsxImageProfile "ESXi-5.1*" -Softwaredepot $basedepot | foreach { $iplist += $_ }
                                        Get-EsxImageProfile "ESXi-5.5*" -Softwaredepot $basedepot | foreach { $iplist += $_ }
                                        Get-EsxImageProfile "ESXi-6.0*" -Softwaredepot $basedepot | foreach { $iplist += $_ }
                                        Get-EsxImageProfile "ESXi-6.5*" -Softwaredepot $basedepot | foreach { $iplist += $_ }
                                        Get-EsxImageProfile "ESXi-6.7*" -Softwaredepot $basedepot | foreach { $iplist += $_ }
                                        Get-EsxImageProfile "ESXi-7.0*" -Softwaredepot $basedepot | foreach { $iplist += $_ }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        if ($iplist.Length -eq 0) {
            write-host -F Red " [FAILED]`n`nFATAL ERROR: No valid ImageProfile(s) found!"
            if ($OfflineBundle) {
                write-host -F Red "The input file is probably not a full ESXi base bundle.`n"
            }
            exit
        } else {
            Write-Verbose -Message "[OK]"
            $iplist = @( $iplist | Sort-Object -Descending -Property @{Expression = { $_.Name.Substring(0, 10) } }, @{Expression = { $_.CreationTime.Date } }, Name )
        }

        # if -sip then display menu of available image profiles ...
        if ($ImageProfile) {
            if ($Update) {
                write-host "Select ImageProfile to use for update:"
            } else {
                write-host "Select Base ImageProfile:"
            }
            write-host "-------------------------------------------"
            for ($i = 0; $i -lt $iplist.Length; $i++ ) {
                write-host ($i + 1): $iplist[$i].Name
            }
            write-host "-------------------------------------------"
            do {
                $sel = read-host "Enter selection"
                if (isNumeric $sel) {
                    if (([int]$sel -lt 1) -or ([int]$sel -gt $iplist.Length)) { $sel = $null }
                } else {
                    $sel = $null
                }
            } until ($sel)
            $idx = [int]$sel - 1
        } else {
            $idx = 0
        }
        if ($Update) {
            $updIP = $iplist[$idx]
        } else {
            $CloneIP = $iplist[$idx]
        }

        write-host ("Using ImageProfile " + $CloneIP.Name + " ...")
        write-host ("(Dated " + $CloneIP.CreationTime + ", AcceptanceLevel: " + $CloneIP.AcceptanceLevel + ",")
        write-host ($CloneIP.Description + ")")

        # If customization is required ...
        if ( ($PackagePath -ne @()) -or $Update -or ($load -ne @()) -or ($RemovePackage -ne @()) ) {

            # Create your own ImageProfile
            if ($ImageProfileName -eq "") { $ImageProfileName = $CloneIP.Name + "-customized" }
            if ($ImageProfileVendor -eq "") { $ImageProfileVendor = $CloneIP.Vendor }
            if ($ImageProfileDescription -eq "") { $ImageProfileDescription = $CloneIP.Description + " (customized)" }
            $MyProfile = New-EsxImageProfile -CloneProfile $CloneIP -Vendor $ImageProfileVendor -Name $ImageProfileName -Description $ImageProfileDescription

            # Update from Online depot profile
            if ($Update) {
                write-host ("Updating with the VMware ImageProfile " + $UpdIP.Name + " ...")
                write-host ("(Dated " + $UpdIP.CreationTime + ", AcceptanceLevel: " + $UpdIP.AcceptanceLevel + ",")
                write-host ($UpdIP.Description + ")")
                $diff = Compare-EsxImageProfile $MyProfile $UpdIP
                $diff.UpgradeFromRef | foreach {
                    $uguid = $_
                    $uvib = Get-EsxSoftwarePackage | where { $_.Guid -eq $uguid }
                    Write-Verbose -Message "   Add VIB" $uvib.Name $uvib.Version
                    AddVIB2Profile $uvib
                }
            }

            # Loop over Offline bundles and VIB files
            if ($PackagePath -ne @()) {
                write-host "Loading Offline bundles and VIB files from" $PackagePath ...
                foreach ($dir in $PackagePath) {
                    foreach ($obundle in Get-Item $dir\*.zip) {
                        Write-Verbose -Message "   Loading" $obundle ...
                        if ($ob = Add-EsxSoftwaredepot $obundle -ErrorAction SilentlyContinue) {
                            Write-Verbose -Message "[OK]"
                            $ob | Get-EsxSoftwarePackage | foreach {
                                Write-Verbose -Message "      Add VIB" $_.Name $_.Version
                                AddVIB2Profile $_
                            }
                        } else {
                            write-host -F Red " [FAILED]`n      Probably not a valid Offline bundle, ignoring."
                        }
                    }
                    foreach ($vibFile in Get-Item $dir\*.vib) {
                        Write-Verbose -Message "   Loading" $vibFile ...
                        try {
                            $vib1 = Get-EsxSoftwarePackage -PackageUrl $vibFile -ErrorAction SilentlyContinue
                            Write-Verbose -Message "[OK]"
                            Write-Verbose -Message "      Add VIB" $vib1.Name $vib1.Version
                            AddVIB2Profile $vib1
                        } catch {
                            write-host -F Red " [FAILED]`n      Probably not a valid VIB file, ignoring."
                        }
                    }
                }
            }
            # Load additional packages from Online depots or Offline bundles
            if ($load -ne @()) {
                write-host "Load additional VIBs from Online depots ..."
                for ($i = 0; $i -lt $load.Length; $i++ ) {
                    if ($ovib = Get-ESXSoftwarePackage $load[$i] -Newest) {
                        Write-Verbose -Message "   Add VIB" $ovib.Name $ovib.Version
                        AddVIB2Profile $ovib
                    } else {
                        write-host -F Red "   [ERROR] Cannot find VIB named" $load[$i] "!"
                    }
                }
            }
            # Remove selected VIBs
            if ($RemovePackage -ne @()) {
                write-host "Remove selected VIBs from ImageProfile ..."
                for ($i = 0; $i -lt $RemovePackage.Length; $i++ ) {
                    Write-Verbose -Message "      Remove VIB" $RemovePackage[$i]
                    try {
                        Remove-EsxSoftwarePackage -ImageProfile $MyProfile -SoftwarePackage $RemovePackage[$i] | Out-Null
                        Write-Verbose -Message "[OK]"
                    } catch {
                        write-host -F Red " [FAILED]`n      VIB does probably not exist or cannot be removed without breaking dependencies."
                    }
                }
            }

        } else {
            $MyProfile = $CloneIP
        }


        # Build the export command:
        $cmd = "Export-EsxImageProfile -ImageProfile " + "`'" + $MyProfile.Name + "`'"

        if ($OutBundle) {
            $outFile = "`'" + $Path + "\" + $MyProfile.Name + ".zip" + "`'"
            $cmd = $cmd + " -ExportTobundle"
        } else {
            $outFile = "`'" + $Path + "\" + $MyProfile.Name + ".iso" + "`'"
            $cmd = $cmd + " -ExportToISO"
        }
        $cmd = $cmd + " -FilePath " + $outFile
        if ($NoSignatureCheck) { $cmd = $cmd + " -NoSignatureCheck" }
        $cmd = $cmd + " -Force"

        # Run the export:
        Write-Verbose -Message ("Exporting the ImageProfile to " + $outFile + ". Please be patient ...")
        if ($test) {
            write-host -F Yellow " [Skipped]"
        } else {
            write-host ""
            Invoke-Expression $cmd
        }

        write-host -F Green "All done.`n"

        # The main catch ...
    } catch {
        write-host -F Red ("`nAn unexpected error occurred:`n" + $Error[0])
        write-host -F Red ("If requesting support please be sure to include the log file`n   " + $log + "`n")

        # The main cleanup
    } finally {
        cleanup
        if (!($PSBoundParameters.ContainsKey('log')) -and $PSBoundParameters.ContainsKey('outDir') -and ($outFile -like '*zip*')) {
            $finalLog = ($Path + "\" + $MyProfile.Name + ".zip" + "-" + (get-date -Format yyyyMMddHHmm) + ".log")
            Move-Item $log $finalLog -force
            write-host ("(Log file moved to " + $finalLog + ")`n")
        } elseif (!($PSBoundParameters.ContainsKey('log')) -and $PSBoundParameters.ContainsKey('outDir') -and ($outFile -like '*iso*')) {
            $finalLog = ($Path + "\" + $MyProfile.Name + ".iso" + "-" + (Get-Date -Format yyyyMMddHHmm) + ".log")
            Move-Item $log $finalLog -force
            write-host ("(Log file moved to " + $finalLog + ")`n")
        }
    }
} end {
    if ($DefaultSoftwaredepots) { Remove-EsxSoftwaredepot $DefaultSoftwaredepots }
}
}