PCITree.ps1: List PCIe Devices on Windows
===

With [this tool](https://github.com/armaber/scripts/blob/main/PCITree/PCITree.ps1), 
the PCIe hierarchy is retrieved and represented either as console *highlighted*
or *html*.

```powershell
    $filter = "ConfigManagerErrorCode != $($script:ProblemNames.CM_PROB_PHANTOM) AND " +
              "(DeviceID LIKE ""PCI\\%"" OR DeviceID LIKE ""ACPI\\PNP0A08\\%"")";
    $ap = Get-WmiObject Win32_PnPEntity -Filter $filter;
```

For each device, be it *ACPI* root complex or true PCIe, a number of properties are displayed.
For brevity, the console variant `-AsVT` or `-AsText` does not display the *driver stack*.

The script requires powershell 5.0 Desktop edition. `GetDeviceProperties` method is not
available on `pwsh.exe` Core. At the expense of a performance penalty, it is possible to
replace the method with `Get-PnPDeviceProperty` cmdlet.

```powershell
    $ret = $ap | Select-Object `
        @{ Name="BARs";
        Expression={ $id = $_.DeviceID; ($ba | Where-Object { $_.DeviceID -eq $id }).BAR }
        },
        @{ Name="Service";
        Expression={ if ($_.Service) { $_.Service } else {
                $_.GetDeviceProperties("DEVPKEY_Device_DriverInfSection").deviceProperties.Data 
                }
            }
        };
```

When arranging the elements, the `Parent` is used to build a list of `Descendant`s.
An element has one parent, multiple descendants. Before computing the descendants,
the list is sorted by BDF, then ACPI root complexes are given priority: the *BDF*
sort can place the RC in random places. On systems with multiple root complexes,
the `ACPI\PNP0A08\` device ID has a suffix in hexadecimal. To keep the overall BDF
listing in ascending order, the suffix is used to order the RCs.

```powershell
    $List.Value = $List.Value | Sort-Object BDF;
    $acpi = @($List.Value | Where-Object { $_.DeviceID -like 'ACPI\PNP0A08\*' } | Sort-Object `
                @{ Expression={[Int]("0x"+($_.DeviceID -split '\\')[-1])} });
    $pci = $List.Value | Where-Object { $_.DeviceID -like 'PCI\*' };
    $List.Value = $acpi + $pci;
```

*BARs* are computed with `CM_Get_First_Log_Conf` and `CM_Get_Res_Des_Data` Win32API.
`Win32_PnPAllocatedResource, Win32_DeviceMemoryAddress` associators lead to false
positives: the BARs discovered are not unique and 64-bit BARs are truncated to 32-bit.
`MEM_RESOURCE` structure is marked as *unsafe*: *MD_Alloc_Base, MD_Alloc_End* are padded.

The `-AsHTML` variant is fully fledged: driver stack, NUMA node, problem code linked
to official documentation, number of processor packages are among the properties being
displayed. *Native hot-plug interrupts granted by firmware* indicates system support
for adapter hot remove/add.

Notes
---
* Use `Set-ExecutionPolicy Bypass -Scope Process` before launching the script.
* Root complexes are discovered on UEFI systems. Legacy `ACPI\PNP0A03` are not
  represented; all descendants are shown on the *1<sup>st</sup> column*.
* Heavy `<table>` usage leads to gaps on rendering the contracted descendants.
* [lspci windows](https://eternallybored.org/misc/pciutils/) is currently blacklisted by
  the browser.
* *Phantom devices* with `CM_PROB_PHANTOM` are non-present adapters, whose registry 
  configuration remain present. These are skipped to prevent false positives.
