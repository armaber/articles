PCIe Device Listing on Windows
===

With [PCITree.ps1](https://github.com/armaber/scripts/blob/main/PCITree/PCITree.ps1), 
the PCIe hierarchy is retrieved and represented either as console *highlighted*
or *html*. IT personnel can use or expand the tool in support cases.

This excerpt represents the bulk:

```powershell
    $filter = "ConfigManagerErrorCode != $($script:ProblemNames.CM_PROB_PHANTOM) AND " +
              "(DeviceID LIKE ""PCI\\%"" OR DeviceID LIKE ""ACPI\\PNP0A08\\%"")";
    $ap = Get-WmiObject Win32_PnPEntity -Filter $filter;
```

* *Phantom devices* are devnodes stored in registry without a physical adapter plugged
  in the system. These are skipped to prevent false positives.
* `ACPI\PNP0A08` root complexes are enumerated on UEFI systems. Legacy `ACPI\PNP0A03`
  are not represented.

For each device, be it *ACPI* root complex, PCIe switch or endpoint, a number of properties
are displayed. The console options `-AsVT` or `-AsText` do not show the *driver stack*.

The script requires powershell 5.0 *Desktop* edition. `GetDeviceProperties` method is not
available under *pwsh.exe* *Core* with `Get-CimInstance`. At the expense of a performance penalty,
it can be replaced with `Get-PnPDeviceProperty` cmdlet and have full support for *Core*.

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

An element in the hierarchy has one `DEVPKEY_Device_Parent`, multiple `Descendant`s.
Before computing the descendants, the list is sorted by BDF, then ACPI root complexes
are given priority: 

* *BDF* sort can place the RC at random indexes among PCIe devices with same `0:0.0`
  location. 

On systems with multiple root complexes, the `ACPI\PNP0A08\`
device ID has a suffix in hexadecimal. Sorting by suffix keeps the overall tree
representation consistent.

```powershell
    $List.Value = $List.Value | Sort-Object BDF;
    $acpi = @($List.Value | Where-Object { $_.DeviceID -like 'ACPI\PNP0A08\*' } | Sort-Object `
                @{ Expression={ [Int]("0x"+($_.DeviceID -split '\\')[-1]) } });
    $pci = $List.Value | Where-Object { $_.DeviceID -like 'PCI\*' };
    $List.Value = $acpi + $pci;
```

*Base address registers* are computed with `CM_Get_First_Log_Conf` and `CM_Get_Res_Des_Data`
Win32APIs.

* `Win32_PnPAllocatedResource, Win32_DeviceMemoryAddress` associators lead to false
positives: the BARs are not unique, 64-bit BARs are truncated to 32-bit.

For brevity, `MEM_RESOURCE` structure is marked as *unsafe*: `MD_Alloc_Base`, `MD_Alloc_End`
are padded.

`-AsHTML` cli switch is fully fledged: driver stack, NUMA node, problem code linked
to documentation, number of processor packages are among the properties being displayed.
*"Native hot-plug interrupts granted by firmware"* indicates platform support for adapter
hot remove/add.

Notes
---
* Use `Set-ExecutionPolicy Bypass -Scope Process` before launching the script.
* Heavy `<table>` usage leads to gaps on rendering the contracted descendants.
* [lspci windows](https://eternallybored.org/misc/pciutils/) is currently blacklisted by
  the browser.
* A progress bar shows the amount of devices enumerated until completion. Large PCIe
  hierarchy with hundreds of devices takes 20+ seconds to be shown.
