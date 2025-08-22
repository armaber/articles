KMDF Logging from User Mode
===

A colleague reported a `WdfRegistryOpenKey` failure when called inside `EvtDriverCleanup`.
In [Kernel Mode Driver Framework](https://github.com/microsoft/Windows-Driver-Frameworks.git),
an internal *Commit* returns *STATUS_DELETE_PENDING*:

```c
if (m_ObjectState != FxObjectStateCreated) {
    TraceDroppedEvent(FxObjectDroppedEventAssignParentObject);
    m_SpinLock.Release(oldIrql);
    return STATUS_DELETE_PENDING;
}
```

Part of the KMDF architecture is the object hierarchy tenet. Each object has a parent.
The object is deleted on demand with `WdfObjectDelete` or implicitly when the parent is
deleted. For `WdfRegistryOpenKey(WDF_NO_OBJECT_ATTRIBUTES)`, the default parent is the
`Driver` object.

*We've learnt that no objects can be created in the parent's lifetime demotion.*

One way to reveal the root cause is through **IFR** = In-Flight Recorder mechanism.

*This guide is an IFR overview, with its valuable traces and convoluted setup.*

IFR Setup
-

IFR is a logging mechanism, developed as a [**WPP** = Windows Software Trace Preprocessor](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/wpp-software-tracing) provider.
IFR is embedded in **Wdf01000.sys**', or it can be developed within a driver.

To use IFR, provider flags must be turned on and a trace session must be launched.

On the KMDF plane, `WdfVerifier.exe` turns on or off settings for particular drivers / DOs.
Launch it on the target system, use the following settings within the **Drivers** tab:

- navigate to *<IHV_Driver>*, expand
- *right-click* on **VerifierOn is always OFF**
- *right-click* on **VerboseOn OFF**
- *right-click* on **Track handles is not active**, select **Track all handle references**
- click **Apply**

Start a trace session:

```powershell
$KmdfProviderName = "KMDFv1 Trace Provider";
(& logman.exe query providers | Select-String $KmdfProviderName) -match "\{(?<guid>.+)\}" | Out-Null;
$KmdfGuid = $Matches["guid"];
$Keywords = "0xFFFFFFFF";
$Level = "5";
$CtlFile = "C:\KmdfIfr.ctl";
"$KmdfGuid;$Keywords;$Level" | Set-Content $CtlFile;

$TraceFile = "C:\KmdfSession.etl";
$TraceLogExe = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\tracelog.exe";
& $TraceLogExe -f $TraceFile -start kmdfsession -guid $CtlFile;
```

`tracelog` requires the **provider** GUID, **keywords** and **level**. The events are stored in
`C:\KmdfSession.etl`. **Keywords** represent a bitmask encoded in
`src\framework\shared\inc\private\common\fxtrace.h`.
**Level** is specified in `src\framework\shared\inc\private\common\dbgtrace.h`.
The values are visible in *Wdf01000.mof*.

<details><summary>keywords=trace flags + level</summary>

```
//ModuleName = Wdf01000KmdfTraceGuid     (Init called in Function FxTraceInitialize)
[Dynamic,
 Description("Wdf01000_KmdfTraceGuid"),
 guid("{544d4c9d-942c-46d5-bf50-df5cd9524a50}"),
 locale("MS\\0x409")]
class Wdf01000KmdfTraceGuid : EventTrace
{
    [Description ("Enable Flags") : amended,
        ValueDescriptions{
             "TRACINGFULL Flag",
             "TRACINGERROR Flag",
             "TRACINGDBGPRINT Flag",
             "TRACINGFRAMEWORKS Flag",
             "TRACINGAPI Flag",
             "TRACINGAPIERROR Flag",
             "TRACINGRESOURCES Flag",
             "TRACINGLOCKING Flag",
             "TRACINGCONTEXT Flag",
             "TRACINGPOOL Flag",
             "TRACINGHANDLE Flag",
             "TRACINGPNP Flag",
             "TRACINGIO Flag",
             "TRACINGIOTARGET Flag",
             "TRACINGDMA Flag",
             "TRACINGREQUEST Flag",
             "TRACINGDRIVER Flag",
             "TRACINGDEVICE Flag",
             "TRACINGUSEROBJECT Flag",
             "TRACINGOBJECT Flag",
             "TRACINGPNPPOWERSTATES Flag",
             "TRACINGIFRCAPTURE Flag"},
        DefineValues{
             "TRACINGFULL",
             "TRACINGERROR",
             "TRACINGDBGPRINT",
             "TRACINGFRAMEWORKS",
             "TRACINGAPI",
             "TRACINGAPIERROR",
             "TRACINGRESOURCES",
             "TRACINGLOCKING",
             "TRACINGCONTEXT",
             "TRACINGPOOL",
             "TRACINGHANDLE",
             "TRACINGPNP",
             "TRACINGIO",
             "TRACINGIOTARGET",
             "TRACINGDMA",
             "TRACINGREQUEST",
             "TRACINGDRIVER",
             "TRACINGDEVICE",
             "TRACINGUSEROBJECT",
             "TRACINGOBJECT",
             "TRACINGPNPPOWERSTATES",
             "TRACINGIFRCAPTURE"},
        Values{
             "TRACINGFULL",
             "TRACINGERROR",
             "TRACINGDBGPRINT",
             "TRACINGFRAMEWORKS",
             "TRACINGAPI",
             "TRACINGAPIERROR",
             "TRACINGRESOURCES",
             "TRACINGLOCKING",
             "TRACINGCONTEXT",
             "TRACINGPOOL",
             "TRACINGHANDLE",
             "TRACINGPNP",
             "TRACINGIO",
             "TRACINGIOTARGET",
             "TRACINGDMA",
             "TRACINGREQUEST",
             "TRACINGDRIVER",
             "TRACINGDEVICE",
             "TRACINGUSEROBJECT",
             "TRACINGOBJECT",
             "TRACINGPNPPOWERSTATES",
             "TRACINGIFRCAPTURE"},
        ValueMap{
             "0x00000001",
             "0x00000002",
             "0x00000004",
             "0x00000008",
             "0x00000010",
             "0x00000020",
             "0x00000040",
             "0x00000080",
             "0x00000100",
             "0x00000200",
             "0x00000400",
             "0x00000800",
             "0x00001000",
             "0x00002000",
             "0x00004000",
             "0x00008000",
             "0x00010000",
             "0x00020000",
             "0x00040000",
             "0x00080000",
             "0x00100000",
             "0x00200000"}: amended
    ]
    uint32 Flags;
    [Description ("Levels") : amended,
        ValueDescriptions{
            "Abnormal exit or termination",
            "Severe errors that need logging",
            "Warnings such as allocation failure",
            "Includes non-error cases",
            "Detailed traces from intermediate steps" } : amended,
         DefineValues{
            "TRACE_LEVEL_FATAL",
            "TRACE_LEVEL_ERROR",
            "TRACE_LEVEL_WARNING"
            "TRACE_LEVEL_INFORMATION",
            "TRACE_LEVEL_VERBOSE" },
        Values{
            "Fatal",
            "Error",
            "Warning",
            "Information",
            "Verbose" },
        ValueMap{
            "0x1",
            "0x2",
            "0x3",
            "0x4",
            "0x5" },
        ValueType("index")
    ]
    uint32 Level;
};
```

</details>

Problem Replication
-

```powershell
$Endpoints = Get-PnpDevice "<VendorID>" -PresentOnly;
$Endpoints | Disable-PnpDevice;

& $TraceLogExe -stop kmdfsession;
```

Log Extraction
-

With trace session stopped, the `.etl` file is processed by `tracefmt`. A prerequisite
for parsing the binary file is the presence of the `wdf01000.pdb` file. This file is part of
the build process for KMDF, available in the public server.

**Note:** *tracefmt* operates on PDBs and images, or it uses `.tmf` = trace message files.
The files shipped with WDK may not match the internal representation. Using PDBs and images
is a reliable method to decode the binary log.

```powershell
$SymChkExe = "C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\symchk.exe";
$LocalSym = "C:\Symbols";
$SymbolServer = "srv*$LocalSym*https://msdl.microsoft.com/download/symbols";

& $SymChkExe C:\Windows\System32\drivers\wdf01000.sys /su $SymbolServer;
```

`symchk` downloads the `.pdb` file using a *refresh* `/su` switch.

**Note:** There are many versions of *wdf01000.sys*. The local `C:\Symbols` directory
keeps track of each *.pdb* in separate subdirectories.

```powershell
$TraceFmtExe = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\tracefmt.exe";
& $TraceFmtExe $TraceFile -i C:\Windows\System32\drivers\wdf01000.sys -r $LocalSym;

Logfile C:\KmdfSession.Etl:
        OS version              10.0.22000  (Currently running on 10.0.22000)
        Start Time              2025-08-21-09:45:45.329
        End Time                2025-08-21-09:46:42.717
        Timezone is             @tzres.dll,-362 (Bias is -120mins)
        BufferSize              65536 B
        Maximum File Size       0 MB
        Buffers  Written        5
        Logger Mode Settings    (0) Logfile Mode is not set
        ProcessorCount          4

Processing completed   Buffers: 5, Events: 209, EventsLost: 0 :: Format Errors: 0, Unknowns: 0

Event traces dumped to FmtFile.txt
Event Summary dumped to FmtSum.txt
```

<details><summary>FmtFile.txt</summary>

```text
[3]0004.183C::08/21/2025-09:46:11.485 [core]FxIFR logging started
[3]0004.183C::08/21/2025-09:46:11.485 [km]Initializing Pool 0xFFFF910FBEF98BB0, Tracking 1
[0]0004.183C::08/21/2025-09:46:11.496 [km]Object FFFF910FC19764D0, WDFOBJECT 00006EF03E689B28 transitioning from FxObjectStateCreated to FxObjectStateDeletedDisposing
[0]0004.183C::08/21/2025-09:46:11.496 [km]Object FFFF910FC19764D0, WDFOBJECT 00006EF03E689B28 transitioning from FxObjectStateDeletedDisposing to FxObjectStateDeletedAndDisposed
[0]0004.183C::08/21/2025-09:46:11.496 [km]Object FFFF910FC19764D0, WDFOBJECT 00006EF03E689B28 transitioning from FxObjectStateDeletedAndDisposed to FxObjectStateDestroyed
[0]0004.183C::08/21/2025-09:46:11.496 [km]Enter AddDevice PDO FFFF910FB4C88360
[0]0004.183C::08/21/2025-09:46:11.496 [km]Constructed FxPkgIo 0xFFFF910FC0ABAE40
[0]0004.183C::08/21/2025-09:46:11.496 [km]Object Type 0x1036 does not have a lock order defined in fx\inc\FxVerifierLock.hpp
[0]0004.183C::08/21/2025-09:46:11.496 [km]Object Type 0x1036 does not have a lock order defined in fx\inc\FxVerifierLock.hpp
[0]0004.183C::08/21/2025-09:46:11.496 [km]Adding FxChildList FFFF910FBD28DE30, WDFCHILDLIST 00006EF042D721C8
[0]0004.183C::08/21/2025-09:46:11.496 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering PnP State WdfDevStatePnpInit from WdfDevStatePnpObjectCreated
[0]0004.183C::08/21/2025-09:46:11.496 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0, IRP_MJ_PNP, 0x00000008(IRP_MN_QUERY_INTERFACE) IRP 0xFFFF910FC27F9DB0
[0]0004.183C::08/21/2025-09:46:11.496 [km]Entering QueryInterface handler
[0]0004.183C::08/21/2025-09:46:11.496 [km]Exiting QueryInterface handler, 0xc00000bb(STATUS_NOT_SUPPORTED)
[0]0004.183C::08/21/2025-09:46:11.496 [km]Object FFFF910FC19764D0, WDFOBJECT 00006EF03E689B28 transitioning from FxObjectStateCreated to FxObjectStateDeletedDisposing
[0]0004.183C::08/21/2025-09:46:11.496 [km]Object FFFF910FC19764D0, WDFOBJECT 00006EF03E689B28 transitioning from FxObjectStateDeletedDisposing to FxObjectStateDeletedAndDisposed
[0]0004.183C::08/21/2025-09:46:11.496 [km]Object FFFF910FC19764D0, WDFOBJECT 00006EF03E689B28 transitioning from FxObjectStateDeletedAndDisposed to FxObjectStateDestroyed
[0]0004.183C::08/21/2025-09:46:11.496 [km]Exit, status STATUS_SUCCESS
[0]0004.183C::08/21/2025-09:46:11.496 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0, IRP_MJ_PNP, !0x18! IRP 0xFFFF910FC27F9DB0
[0]0004.183C::08/21/2025-09:46:11.496 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0, IRP_MJ_PNP, 0x0000000d(IRP_MN_FILTER_RESOURCE_REQUIREMENTS) IRP 0xFFFF910FC27F9DB0
[0]0004.183C::08/21/2025-09:46:11.496 [km]Entering FilterResourceRequirements handler
[0]0004.183C::08/21/2025-09:46:11.496 [km]Exiting FilterResourceRequirements handler, STATUS_SUCCESS
[0]0004.183C::08/21/2025-09:46:11.496 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0, IRP_MJ_PNP, 0x00000008(IRP_MN_QUERY_INTERFACE) IRP 0xFFFF910FC27F9DB0
[0]0004.183C::08/21/2025-09:46:11.496 [km]Entering QueryInterface handler
[0]0004.183C::08/21/2025-09:46:11.496 [km]Exiting QueryInterface handler, 0xc00000bb(STATUS_NOT_SUPPORTED)
[0]0004.183C::08/21/2025-09:46:11.499 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0, IRP_MJ_PNP, 0x00000000(IRP_MN_START_DEVICE) IRP 0xFFFF910FC27F9DB0
[0]0004.183C::08/21/2025-09:46:11.499 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering PnP State WdfDevStatePnpInitStarting from WdfDevStatePnpInit
[2]0004.0114::08/21/2025-09:46:11.533 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering PnP State WdfDevStatePnpHardwareAvailable from WdfDevStatePnpInitStarting
[2]0004.0114::08/21/2025-09:46:11.533 [km]Entering PnpMatchResources
[2]0004.0114::08/21/2025-09:46:11.533 [km]Is MSI? 1, MSI-ID 0, AffinityPolicy WdfIrqPolicyOneCloseProcessor, Priority WdfIrqPriorityUndefined, Group 0, Affinity 0xf, Irql 0x6, Vector 0x61
[2]0004.0114::08/21/2025-09:46:11.533 [km]Is MSI? 1, MSI-ID 1, AffinityPolicy WdfIrqPolicyOneCloseProcessor, Priority WdfIrqPriorityUndefined, Group 0, Affinity 0xf, Irql 0x5, Vector 0x51
[2]0004.0114::08/21/2025-09:46:11.533 [km]Is MSI? 1, MSI-ID 2, AffinityPolicy WdfIrqPolicyOneCloseProcessor, Priority WdfIrqPriorityUndefined, Group 0, Affinity 0xf, Irql 0xb, Vector 0xb2
[2]0004.0114::08/21/2025-09:46:11.533 [km]Is MSI? 1, MSI-ID 3, AffinityPolicy WdfIrqPolicyOneCloseProcessor, Priority WdfIrqPriorityUndefined, Group 0, Affinity 0xf, Irql 0xa, Vector 0xa2
[2]0004.0114::08/21/2025-09:46:11.533 [km]Exiting PnpMatchResources STATUS_SUCCESS
[2]0004.0114::08/21/2025-09:46:11.533 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0, IRP_MJ_PNP, 0x00000008(IRP_MN_QUERY_INTERFACE) IRP 0xFFFF910FC0FF1DB0
[2]0004.0114::08/21/2025-09:46:11.533 [km]Entering QueryInterface handler
[2]0004.0114::08/21/2025-09:46:11.533 [km]Exiting QueryInterface handler, 0xc00000bb(STATUS_NOT_SUPPORTED)
[2]0004.0114::08/21/2025-09:46:11.533 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0, IRP_MJ_PNP, 0x00000008(IRP_MN_QUERY_INTERFACE) IRP 0xFFFF910FC0FF1DB0
[2]0004.0114::08/21/2025-09:46:11.533 [km]Entering QueryInterface handler
[2]0004.0114::08/21/2025-09:46:11.533 [km]Exiting QueryInterface handler, 0xc00000bb(STATUS_NOT_SUPPORTED)
[2]0004.0114::08/21/2025-09:46:11.533 [km]exit WDFDEVICE 00006EF041D6ACA8, Property 14, STATUS_SUCCESS
[2]0004.0114::08/21/2025-09:46:11.533 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0, IRP_MJ_PNP, 0x00000009(IRP_MN_QUERY_CAPABILITIES) IRP 0xFFFF910FC0FF1DB0
[2]0004.0114::08/21/2025-09:46:11.533 [km]Entering QueryCapabilities handler
[2]0004.0114::08/21/2025-09:46:11.533 [km]Exiting QueryCapabilities handler
[2]0004.0114::08/21/2025-09:46:11.533 [km]Entering QueryCapabilities completion handler
[2]0004.0114::08/21/2025-09:46:11.533 [km]Exiting QueryCapabilities completion handler
[2]0004.0114::08/21/2025-09:46:11.533 [km]exit WDFDEVICE 00006EF041D6ACA8, Property 16, STATUS_SUCCESS
[2]0004.0114::08/21/2025-09:46:11.533 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0, IRP_MJ_PNP, 0x00000009(IRP_MN_QUERY_CAPABILITIES) IRP 0xFFFF910FC0FF1DB0
[2]0004.0114::08/21/2025-09:46:11.533 [km]Entering QueryCapabilities handler
[2]0004.0114::08/21/2025-09:46:11.533 [km]Exiting QueryCapabilities handler
[2]0004.0114::08/21/2025-09:46:11.533 [km]Entering QueryCapabilities completion handler
[2]0004.0114::08/21/2025-09:46:11.533 [km]Exiting QueryCapabilities completion handler
[2]0004.0114::08/21/2025-09:46:11.533 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering power policy state WdfDevStatePwrPolStarting from WdfDevStatePwrPolObjectCreated
[2]0004.0114::08/21/2025-09:46:11.533 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering power idle state FxIdleStarted from FxIdleStopped
[2]0004.0114::08/21/2025-09:46:11.533 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering Power State WdfDevStatePowerStartingCheckDeviceType from WdfDevStatePowerObjectCreated
[2]0004.0114::08/21/2025-09:46:11.533 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering Power State WdfDevStatePowerD0Starting from WdfDevStatePowerStartingCheckDeviceType
[2]0004.0114::08/21/2025-09:46:11.534 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering Power State WdfDevStatePowerD0StartingConnectInterrupt from WdfDevStatePowerD0Starting
[3]0004.0114::08/21/2025-09:46:11.534 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering Power State WdfDevStatePowerD0StartingDmaEnable from WdfDevStatePowerD0StartingConnectInterrupt
[3]0004.0114::08/21/2025-09:46:11.534 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering Power State WdfDevStatePowerD0StartingPostHardwareEnabled from WdfDevStatePowerD0StartingDmaEnable
[3]0004.0114::08/21/2025-09:46:11.534 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering Power State WdfDevStatePowerD0StartingStartSelfManagedIo from WdfDevStatePowerD0StartingPostHardwareEnabled
[3]0004.0114::08/21/2025-09:46:11.534 [km]Power resume all queues of WDFDEVICE 0x00006EF041D6ACA8
[3]0004.0114::08/21/2025-09:46:11.534 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering power idle state FxIdleStartedPowerUp from FxIdleStarted
[3]0004.0114::08/21/2025-09:46:11.534 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering power idle state FxIdleDisabled from FxIdleStartedPowerUp
[3]0004.0114::08/21/2025-09:46:11.534 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering Power State WdfDevStatePowerDecideD0State from WdfDevStatePowerD0StartingStartSelfManagedIo
[3]0004.0114::08/21/2025-09:46:11.534 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering Power State WdfDevStatePowerD0 from WdfDevStatePowerDecideD0State
[3]0004.0114::08/21/2025-09:46:11.534 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering power policy state WdfDevStatePwrPolStartingPoweredUp from WdfDevStatePwrPolStarting
[3]0004.0114::08/21/2025-09:46:11.534 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering power policy state WdfDevStatePwrPolStartingSucceeded from WdfDevStatePwrPolStartingPoweredUp
[3]0004.0114::08/21/2025-09:46:11.534 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering power policy state WdfDevStatePwrPolStartingDecideS0Wake from WdfDevStatePwrPolStartingSucceeded
[3]0004.0114::08/21/2025-09:46:11.534 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering power policy state WdfDevStatePwrPolStarted from WdfDevStatePwrPolStartingDecideS0Wake
[3]0004.0114::08/21/2025-09:46:11.534 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering power idle state FxIdleDisabled from FxIdleDisabled
[3]0004.0114::08/21/2025-09:46:11.534 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering PnP State WdfDevStatePnpEnableInterfaces from WdfDevStatePnpHardwareAvailable
[3]0004.0114::08/21/2025-09:46:11.534 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering PnP State WdfDevStatePnpStarted from WdfDevStatePnpEnableInterfaces
[3]0004.0114::08/21/2025-09:46:11.534 [km]lastlogged 1dc126197b490de, current 1dc126748204668, delta 5b06bb58a
[2]0004.183C::08/21/2025-09:46:11.534 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0, IRP_MJ_PNP, 0x00000009(IRP_MN_QUERY_CAPABILITIES) IRP 0xFFFF910FC0FF1DB0
[2]0004.183C::08/21/2025-09:46:11.534 [km]Entering QueryCapabilities handler
[2]0004.183C::08/21/2025-09:46:11.534 [km]Exiting QueryCapabilities handler
[2]0004.183C::08/21/2025-09:46:11.534 [km]Entering QueryCapabilities completion handler
[2]0004.183C::08/21/2025-09:46:11.534 [km]Exiting QueryCapabilities completion handler
[2]0004.183C::08/21/2025-09:46:11.534 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0, IRP_MJ_PNP, 0x00000014(IRP_MN_QUERY_PNP_DEVICE_STATE) IRP 0xFFFF910FC0FF1DB0
[2]0004.183C::08/21/2025-09:46:11.534 [km]Entering QueryPnpDeviceState completion handler
[2]0004.183C::08/21/2025-09:46:11.534 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 returning PNP_DEVICE_STATE 0x0 IRP 0xFFFF910FC0FF1DB0
[2]0004.183C::08/21/2025-09:46:11.534 [km]Exiting QueryPnpDeviceState completion handler
[2]0004.183C::08/21/2025-09:46:11.534 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0, IRP_MJ_PNP, 0x00000007(IRP_MN_QUERY_DEVICE_RELATIONS) type BusRelations IRP 0xFFFF910FC0FF1DB0
[2]0004.183C::08/21/2025-09:46:11.534 [km]Entering QueryDeviceRelations handler, type BusRelations
[2]0004.183C::08/21/2025-09:46:11.534 [core]Nothing to report on WDFCHILDLIST 00006EF042D721C8, returning early
[2]0004.183C::08/21/2025-09:46:11.534 [core]Begin processing modifications on WDFCHILDLIST 00006EF042D721C8
[2]0004.183C::08/21/2025-09:46:11.534 [core]end processing modifications on WDFCHILDLIST 00006EF042D721C8
[2]0004.183C::08/21/2025-09:46:11.534 [core]Begin processing modifications on WDFCHILDLIST 00006EF042D721C8
[2]0004.183C::08/21/2025-09:46:11.534 [core]end processing modifications on WDFCHILDLIST 00006EF042D721C8
[2]0004.183C::08/21/2025-09:46:11.534 [km]WDFDEVICE 00006EF041D6ACA8, returning 0xc00000bb(STATUS_NOT_SUPPORTED) from processing bus relations
[2]0004.183C::08/21/2025-09:46:11.534 [km]Exiting QueryDeviceRelations handler, status 0xc00000bb(STATUS_NOT_SUPPORTED)
[3]0004.174C::08/21/2025-09:46:11.534 [wmi]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 IRP_MJ_SYSTEM_CONTROL, 0x0000000b(IRP_MN_REGINFO_EX) IRP 0xFFFF910FBB1E7290
[2]0004.183C::08/21/2025-09:46:15.730 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0, IRP_MJ_PNP, 0x00000007(IRP_MN_QUERY_DEVICE_RELATIONS) type RemovalRelations IRP 0xFFFF910FC0EE9DE0
[2]0004.183C::08/21/2025-09:46:15.730 [km]Entering QueryDeviceRelations handler, type RemovalRelations
[2]0004.183C::08/21/2025-09:46:15.730 [km]Exiting QueryDeviceRelations handler, status 0xc00000bb(STATUS_NOT_SUPPORTED)
[2]0004.183C::08/21/2025-09:46:15.730 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0, IRP_MJ_PNP, 0x00000001(IRP_MN_QUERY_REMOVE_DEVICE) IRP 0xFFFF910FC0EE9DE0
[2]0004.183C::08/21/2025-09:46:15.730 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering PnP State WdfDevStatePnpQueryRemoveStaticCheck from WdfDevStatePnpStarted
[2]0004.183C::08/21/2025-09:46:15.730 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering PnP State WdfDevStatePnpQueryRemoveAskDriver from WdfDevStatePnpQueryRemoveStaticCheck
[2]0004.183C::08/21/2025-09:46:15.730 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering PnP State WdfDevStatePnpQueryRemoveEnsureDeviceAwake from WdfDevStatePnpQueryRemoveAskDriver
[2]0004.183C::08/21/2025-09:46:15.730 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering PnP State WdfDevStatePnpQueryRemovePending from WdfDevStatePnpQueryRemoveEnsureDeviceAwake
[1]0004.183C::08/21/2025-09:46:15.730 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0, IRP_MJ_PNP, 0x00000002(IRP_MN_REMOVE_DEVICE) IRP 0xFFFF910FBE9ADB00
[1]0004.183C::08/21/2025-09:46:15.730 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering PnP State WdfDevStatePnpQueriedRemoving from WdfDevStatePnpQueryRemovePending
[1]0004.183C::08/21/2025-09:46:15.730 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering power policy state WdfDevStatePwrPolStopping from WdfDevStatePwrPolStarted
[1]0004.183C::08/21/2025-09:46:15.730 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering Power State WdfDevStatePowerGotoD3Stopped from WdfDevStatePowerD0
[1]0004.183C::08/21/2025-09:46:15.730 [km]Perform FxIoStopProcessingForPowerHold for all queues of WDFDEVICE 0x00006EF041D6ACA8
[3]0004.183C::08/21/2025-09:46:15.734 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering power idle state FxIdleGoingToDx from FxIdleDisabled
[3]0004.183C::08/21/2025-09:46:15.734 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering power idle state FxIdleInDx from FxIdleGoingToDx
[3]0004.183C::08/21/2025-09:46:15.734 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering Power State WdfDevStatePowerStopped from WdfDevStatePowerGotoD3Stopped
[3]0004.183C::08/21/2025-09:46:15.734 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering power policy state WdfDevStatePwrPolStoppingSendStatus from WdfDevStatePwrPolStopping
[3]0004.183C::08/21/2025-09:46:15.734 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering power idle state FxIdleInDxStopped from FxIdleInDx
[3]0004.183C::08/21/2025-09:46:15.734 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering power idle state FxIdleStopped from FxIdleInDxStopped
[3]0004.183C::08/21/2025-09:46:15.734 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering power policy state WdfDevStatePwrPolStopped from WdfDevStatePwrPolStoppingSendStatus
[3]0004.183C::08/21/2025-09:46:15.734 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering PnP State WdfDevStatePnpRemovingDisableInterfaces from WdfDevStatePnpQueriedRemoving
[3]0004.183C::08/21/2025-09:46:15.735 [km]Perform FxIoStopProcessingForPowerPurgeManaged for all queues of WDFDEVICE 0x00006EF041D6ACA8
[3]0004.183C::08/21/2025-09:46:15.735 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering power policy state WdfDevStatePwrPolStoppedRemoving from WdfDevStatePwrPolStopped
[3]0004.183C::08/21/2025-09:46:15.735 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering power policy state WdfDevStatePwrPolRemoved from WdfDevStatePwrPolStoppedRemoving
[3]0004.183C::08/21/2025-09:46:15.735 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering PnP State WdfDevStatePnpRemoved from WdfDevStatePnpRemovingDisableInterfaces
[3]0004.183C::08/21/2025-09:46:15.735 [core]WDFCHILDLIST 00006EF042D721C8:  removing children
[3]0004.183C::08/21/2025-09:46:15.735 [core]Begin processing modifications on WDFCHILDLIST 00006EF042D721C8
[3]0004.183C::08/21/2025-09:46:15.735 [core]end processing modifications on WDFCHILDLIST 00006EF042D721C8
[3]0004.183C::08/21/2025-09:46:15.735 [core]Begin processing modifications on WDFCHILDLIST 00006EF042D721C8
[3]0004.183C::08/21/2025-09:46:15.735 [core]end processing modifications on WDFCHILDLIST 00006EF042D721C8
[3]0004.183C::08/21/2025-09:46:15.735 [core]Begin processing modifications on WDFCHILDLIST 00006EF042D721C8
[3]0004.183C::08/21/2025-09:46:15.735 [core]end processing modifications on WDFCHILDLIST 00006EF042D721C8
[3]0004.183C::08/21/2025-09:46:15.735 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering PnP State WdfDevStatePnpRemovedChildrenRemoved from WdfDevStatePnpRemoved
[3]0004.183C::08/21/2025-09:46:15.735 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering PnP State WdfDevStatePnpFdoRemoved from WdfDevStatePnpRemovedChildrenRemoved
[3]0004.183C::08/21/2025-09:46:15.735 [km]Perform FxIoStopProcessingForPowerPurgeNonManaged for all queues of WDFDEVICE 0x00006EF041D6ACA8
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBE295350, WDFOBJECT 00006EF041D6ACA8 transitioning from FxObjectStateCreated to FxObjectStateDisposingEarly
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBE295350, WDFOBJECT 00006EF041D6ACA8 transitioning from FxObjectStateDisposingEarly to FxObjectStateDisposingDisposeChildren
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBE7FDA70, WDFOBJECT 00006EF041802588 transitioning from FxObjectStateCreated to FxObjectStateDisposingEarly
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBE7FDA70, WDFOBJECT 00006EF041802588 transitioning from FxObjectStateDisposingEarly to FxObjectStateDisposingDisposeChildren
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBE7FDA70, WDFOBJECT 00006EF041802588 transitioning from FxObjectStateDisposingDisposeChildren to FxObjectStateDisposed
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBE7FEC50, WDFOBJECT 00006EF0418013A8 transitioning from FxObjectStateCreated to FxObjectStateDisposingEarly
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBE7FEC50, WDFOBJECT 00006EF0418013A8 transitioning from FxObjectStateDisposingEarly to FxObjectStateDisposingDisposeChildren
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBE7FEC50, WDFOBJECT 00006EF0418013A8 transitioning from FxObjectStateDisposingDisposeChildren to FxObjectStateDisposed
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBD28DE30, WDFOBJECT 00006EF042D721C8 transitioning from FxObjectStateCreated to FxObjectStateDisposingEarly
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBD28DE30, WDFOBJECT 00006EF042D721C8 transitioning from FxObjectStateDisposingEarly to FxObjectStateDisposingDisposeChildren
[3]0004.183C::08/21/2025-09:46:15.735 [km]Removing FxChildList FFFF910FBD28DE30, WDFCHILDLIST 00006EF042D721C8
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBD28DE30, WDFOBJECT 00006EF042D721C8 transitioning from FxObjectStateDisposingDisposeChildren to FxObjectStateDisposed
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBEEF48E0, WDFOBJECT 00006EF04110B718 transitioning from FxObjectStateCreated to FxObjectStateDisposingEarly
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBEEF48E0, WDFOBJECT 00006EF04110B718 transitioning from FxObjectStateDisposingEarly to FxObjectStateDisposingDisposeChildren
[3]0004.183C::08/21/2025-09:46:15.735 [km]WDFIOTARGET 00006EF04110B718, Waiting on Dispose event FFFFA384D008EEF0
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBEEF48E0, WDFOBJECT 00006EF04110B718 transitioning from FxObjectStateDisposingDisposeChildren to FxObjectStateDisposed
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FC0F90620, WDFOBJECT 00006EF03F06F9D8 transitioning from FxObjectStateCreated to FxObjectStateDisposingEarly
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FC0F90620, WDFOBJECT 00006EF03F06F9D8 transitioning from FxObjectStateDisposingEarly to FxObjectStateDisposingDisposeChildren
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FC0F90620, WDFOBJECT 00006EF03F06F9D8 transitioning from FxObjectStateDisposingDisposeChildren to FxObjectStateDisposed
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBDFE7AE0, WDFOBJECT 00006EF042018518 transitioning from FxObjectStateCreated to FxObjectStateDisposingEarly
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBDFE7AE0, WDFOBJECT 00006EF042018518 transitioning from FxObjectStateDisposingEarly to FxObjectStateDisposingDisposeChildren
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBDFE7AE0, WDFOBJECT 00006EF042018518 transitioning from FxObjectStateDisposingDisposeChildren to FxObjectStateDisposed
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FC0EDF640, WDFOBJECT 00006EF03F1209B8 transitioning from FxObjectStateCreated to FxObjectStateDisposingEarly
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FC0EDF640, WDFOBJECT 00006EF03F1209B8 transitioning from FxObjectStateDisposingEarly to FxObjectStateDisposingDisposeChildren
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FC0EDF640, WDFOBJECT 00006EF03F1209B8 transitioning from FxObjectStateDisposingDisposeChildren to FxObjectStateDisposed
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FC0374AF0, WDFOBJECT 00006EF03FC8B508 transitioning from FxObjectStateCreated to FxObjectStateDisposingEarly
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FC0374AF0, WDFOBJECT 00006EF03FC8B508 transitioning from FxObjectStateDisposingEarly to FxObjectStateDisposingDisposeChildren
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FC0374AF0, WDFOBJECT 00006EF03FC8B508 transitioning from FxObjectStateDisposingDisposeChildren to FxObjectStateDisposed
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBE295350, WDFOBJECT 00006EF041D6ACA8 transitioning from FxObjectStateDisposingDisposeChildren to FxObjectStateDisposed
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBE7FDA70, WDFOBJECT 00006EF041802588 transitioning from FxObjectStateDisposed to FxObjectStateDeletedAndDisposed
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBE7FEC50, WDFOBJECT 00006EF0418013A8 transitioning from FxObjectStateDisposed to FxObjectStateDeletedAndDisposed
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBD28DE30, WDFOBJECT 00006EF042D721C8 transitioning from FxObjectStateDisposed to FxObjectStateDeletedAndDisposed
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBEEF48E0, WDFOBJECT 00006EF04110B718 transitioning from FxObjectStateDisposed to FxObjectStateDeletedAndDisposed
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FC0F90620, WDFOBJECT 00006EF03F06F9D8 transitioning from FxObjectStateDisposed to FxObjectStateDeletedAndDisposed
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FC0F90620, WDFOBJECT 00006EF03F06F9D8 transitioning from FxObjectStateDeletedAndDisposed to FxObjectStateDestroyed
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBDFE7AE0, WDFOBJECT 00006EF042018518 transitioning from FxObjectStateDisposed to FxObjectStateDeletedAndDisposed
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBDFE7AE0, WDFOBJECT 00006EF042018518 transitioning from FxObjectStateDeletedAndDisposed to FxObjectStateDestroyed
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FC0EDF640, WDFOBJECT 00006EF03F1209B8 transitioning from FxObjectStateDisposed to FxObjectStateDeletedAndDisposed
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FC0EDF640, WDFOBJECT 00006EF03F1209B8 transitioning from FxObjectStateDeletedAndDisposed to FxObjectStateDestroyed
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FC0374AF0, WDFOBJECT 00006EF03FC8B508 transitioning from FxObjectStateDisposed to FxObjectStateDeletedAndDisposed
[3]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FC0374AF0, WDFOBJECT 00006EF03FC8B508 transitioning from FxObjectStateDeletedAndDisposed to FxObjectStateDestroyed
[3]0004.183C::08/21/2025-09:46:15.735 [km]WDFDEVICE 0x00006EF041D6ACA8 !devobj 0xFFFF910FBEAECDE0 entering PnP State WdfDevStatePnpFinal from WdfDevStatePnpFdoRemoved
[3]0004.183C::08/21/2025-09:46:15.735 [km]WDFDEVICE 00006EF041D6ACA8, !devobj FFFF910FBEAECDE0 waiting for remove event to finish processing
[3]0004.183C::08/21/2025-09:46:15.735 [km]WDFDEVICE 00006EF041D6ACA8, !devobj FFFF910FBEAECDE0 waiting for pnp state machine to finish
[0]0004.183C::08/21/2025-09:46:15.735 [km]Deleting !devobj FFFF910FBEAECDE0, WDFDEVICE 00006EF041D6ACA8, attached to !devobj FFFF910FB4C88360
[0]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBE295350, WDFOBJECT 00006EF041D6ACA8 transitioning from FxObjectStateDisposed to FxObjectStateDeletedAndDisposed
[0]0004.183C::08/21/2025-09:46:15.735 [km]Destroyed FxPkgIo 0xFFFF910FC0ABAE40
[0]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBE295350, WDFOBJECT 00006EF041D6ACA8 transitioning from FxObjectStateDeletedAndDisposed to FxObjectStateDestroyed
[0]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBD28DE30, WDFOBJECT 00006EF042D721C8 transitioning from FxObjectStateDeletedAndDisposed to FxObjectStateDestroyed
[0]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBEEF48E0, WDFOBJECT 00006EF04110B718 transitioning from FxObjectStateDeletedAndDisposed to FxObjectStateDestroyed
[0]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBE7FDA70, WDFOBJECT 00006EF041802588 transitioning from FxObjectStateDeletedAndDisposed to FxObjectStateDestroyed
[0]0004.183C::08/21/2025-09:46:15.735 [km]Object FFFF910FBE7FEC50, WDFOBJECT 00006EF0418013A8 transitioning from FxObjectStateDeletedAndDisposed to FxObjectStateDestroyed
[0]0004.183C::08/21/2025-09:46:15.736 [km]Unloading WDFDRIVER 00006EF03F6B41C8, PDRIVER_OBJECT_UM FFFF910FC0F05E30
[0]0004.183C::08/21/2025-09:46:15.736 [km]Object FFFF910FC094BE30, WDFOBJECT 00006EF03F6B41C8 transitioning from FxObjectStateCreated to FxObjectStateDeletedDisposing
[0]0004.183C::08/21/2025-09:46:15.736 [km]Object FFFF910FC1013750, WDFOBJECT 00006EF03EFEC8A8 transitioning from FxObjectStateCreated to FxObjectStateDisposingEarly
[0]0004.183C::08/21/2025-09:46:15.736 [km]Object FFFF910FC1013750, WDFOBJECT 00006EF03EFEC8A8 transitioning from FxObjectStateDisposingEarly to FxObjectStateDisposingDisposeChildren
[0]0004.183C::08/21/2025-09:46:15.736 [km]Object FFFF910FC1013750, WDFOBJECT 00006EF03EFEC8A8 transitioning from FxObjectStateDisposingDisposeChildren to FxObjectStateDisposed
[0]0004.183C::08/21/2025-09:46:15.736 [km]Object FFFF910FC1013DE0, WDFOBJECT 00006EF03EFEC218 transitioning from FxObjectStateCreated to FxObjectStateDisposingEarly
[0]0004.183C::08/21/2025-09:46:15.736 [km]Object FFFF910FC1013DE0, WDFOBJECT 00006EF03EFEC218 transitioning from FxObjectStateDisposingEarly to FxObjectStateDisposingDisposeChildren
[0]0004.183C::08/21/2025-09:46:15.736 [km]Object FFFF910FC1013DE0, WDFOBJECT 00006EF03EFEC218 transitioning from FxObjectStateDisposingDisposeChildren to FxObjectStateDisposed
[0]0004.183C::08/21/2025-09:46:15.736 [km]Object FFFF910FC094BE30, WDFOBJECT 00006EF03F6B41C8, state FxObjectStateDeletedDisposing dropping event FxObjectDroppedEventAddChildObjectInternal
[0]0004.183C::08/21/2025-09:46:15.736 [km]Object FFFF910FC19755D0, WDFOBJECT 00006EF03E68AA28 transitioning from FxObjectStateCreated to FxObjectStateDeletedDisposing
[0]0004.183C::08/21/2025-09:46:15.736 [km]Object FFFF910FC19755D0, WDFOBJECT 00006EF03E68AA28 transitioning from FxObjectStateDeletedDisposing to FxObjectStateDeletedAndDisposed
[0]0004.183C::08/21/2025-09:46:15.736 [km]Object FFFF910FC19755D0, WDFOBJECT 00006EF03E68AA28 transitioning from FxObjectStateDeletedAndDisposed to FxObjectStateDestroyed
[0]0004.183C::08/21/2025-09:46:15.736 [km]Object FFFF910FC094BE30, WDFOBJECT 00006EF03F6B41C8 transitioning from FxObjectStateDeletedDisposing to FxObjectStateDeletedAndDisposed
[0]0004.183C::08/21/2025-09:46:15.736 [km]Object FFFF910FC1013750, WDFOBJECT 00006EF03EFEC8A8 transitioning from FxObjectStateDisposed to FxObjectStateDeletedAndDisposed
[0]0004.183C::08/21/2025-09:46:15.736 [km]Object FFFF910FC1013750, WDFOBJECT 00006EF03EFEC8A8 transitioning from FxObjectStateDeletedAndDisposed to FxObjectStateDestroyed
[0]0004.183C::08/21/2025-09:46:15.736 [km]Object FFFF910FC1013DE0, WDFOBJECT 00006EF03EFEC218 transitioning from FxObjectStateDisposed to FxObjectStateDeletedAndDisposed
[0]0004.183C::08/21/2025-09:46:15.736 [km]Object FFFF910FC1013DE0, WDFOBJECT 00006EF03EFEC218 transitioning from FxObjectStateDeletedAndDisposed to FxObjectStateDestroyed
[0]0004.183C::08/21/2025-09:46:15.736 [km]Object FFFF910FC094BE30, WDFOBJECT 00006EF03F6B41C8 transitioning from FxObjectStateDeletedAndDisposed to FxObjectStateDestroyed
[0]0004.183C::08/21/2025-09:46:15.736 [km]Destroying Pool 0xFFFF910FBEF98BB0
[0]0004.183C::08/21/2025-09:46:15.736 [km]FxPoolDump: NonPagedBytes 0, PagedBytes 0, NonPagedAllocations 0, PagedAllocations 0,PeakNonPagedBytes 38208, PeakPagedBytes 132,FxPoolDump: PeakNonPagedAllocations 133, PeakPagedAllocations 2
[0]0004.183C::08/21/2025-09:46:15.736 [km]Decrement UnLock counter (0) for Verifier Paged Memory with driver globals FFFF910FBEF98B40
```

</details>

```text
[0]0004.183C::08/21/2025-09:46:15.736 [km]Unloading WDFDRIVER 00006EF03F6B41C8, PDRIVER_OBJECT_UM FFFF910FC0F05E30
[0]0004.183C::08/21/2025-09:46:15.736 [km]Object FFFF910FC094BE30, WDFOBJECT 00006EF03F6B41C8 transitioning from FxObjectStateCreated to FxObjectStateDeletedDisposing
...
[0]0004.183C::08/21/2025-09:46:15.736 [km]Object FFFF910FC094BE30, WDFOBJECT 00006EF03F6B41C8, state FxObjectStateDeletedDisposing dropping event FxObjectDroppedEventAddChildObjectInternal
```

The driver object has transitioned from `FxObjectStateCreated` to `FxObjectStateDeleteDisposing`.
During the *WDFKEY* creation, the state of the driver is compared and the framework *raises the error*.

Notes
-

* WDF prevents objects from being created in the cleanup path.
* KMDF generates the IFR events using a preparation stage:
    * `WdfVerifier.exe` turns on the driver flags on the target system.
    * The trace session is launched and stopped, the resulting file is explored.
    * It is possible to view the traces in the console, using a realtime session.
* The binary file is decoded using the `Wdf01000.sys` image and adjacent `.pdb`.

    ```powershell
    & $SymChkExe C:\Windows\System32\drivers\wdf01000.sys /su $SymbolServer;
    ```
    * `tracepdb` version *10.0.26100.4188* is unusable.

* To postprocess the `.etl`:

    ```powershell
    & $TraceLogExe -f $TraceFile -start kmdfsession -guid $CtlFile;
    & $TraceLogExe -stop kmdfsession;

    & $TraceFmtExe $TraceFile -i C:\Windows\System32\drivers\wdf01000.sys -r $LocalSym;
    ```

* To log the events as they appear:

    ```powershell
    & $TraceLogExe -rt -start kmdfsession -guid $CtlFile;

    & $TraceFmtExe -rt kmdfsession -i C:\Windows\System32\drivers\wdf01000.sys -r $LocalSym -displayonly;
    ```
* `tracefmt` generates a `Wdf01000.mof` file containing the human-readable
   flags and levels. Those can be fed into `-guid <file>.ctl`.
