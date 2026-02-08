CreateFile(KSCATEGORY_VIDEO_CAMERA) fails with STATUS_CANCELLED
===

A developer reported an anomaly surfacing on a CreateFile/CloseHandle loop, using
`KSCATEGORY_VIDEO_CAMERA` interface. It was observed that *CreateFile* fails randomly
with `STATUS_CANCELLED`. The error does not replicate if a delay is placed before the
2<sup>nd</sup> *CreateFile* call.

```c
while (true) {
    HANDLE hFile = CreateFileW(deviceInterface, 0, 0, 0, OPEN_EXISTING, 0, 0);
    if (hFile != INVALID_HANDLE_VALUE) {
        CloseHandle(hFile);
    } else {
        printf("%u 0x%08X\n", i ++, RtlGetLastNtStatus());
    }
}
```

With spare time available, a target machine was set up. The problem replicates both
on *Windows 10* and *11*, as initially reported.

Let's look at CreateFile/CloseHandle call graph in kernel mode. First, **IRP_MJ_CLOSE**:

```
$ImageFile = "C:\Windows\System32\drivers\usbvideo.sys";
& .\UfSymbol.ps1 -Image $ImageFile -Symbol usbvideo!USBVideoFilterClose -Down

usbvideo!USBVideoFilterClose [35]
│                           ⟜usbvideo!_imp_KsGetDevice
│                           ⟜usbvideo!_imp_KeWaitForSingleObject
│                           ⟜usbvideo!_imp_KeReleaseMutex
├──────────────────────────▷usbvideo!SetRegionOfInterestControlToDefaults
│                                                                        usbvideo!SubmitControlRequest
├──────────────────────────▷usbvideo!MSXURestoreDefaults
│                                                       usbvideo!IsSurfaceHubOS
│                           ⟜usbvideo!_imp_IoOpenDeviceRegistryKey
│                           ⟜usbvideo!_imp_RtlInitUnicodeString
│                           ⟜usbvideo!_imp_ZwSetValueKey
│                           ⟜usbvideo!_imp_ZwClose
└──────────────────────────▷usbvideo!PowerDownDevice
                                                    ⟜usbvideo!_imp_IoAcquireRemoveLockEx
                                                    ⟜usbvideo!_imp_KeAcquireSpinLockRaiseToDpc
                                                    ⟜usbvideo!_imp_IoAllocateWorkItem
                                                    ⟜usbvideo!_imp_IoQueueWorkItem
                                                    ⟜usbvideo!_imp_IoReleaseRemoveLockEx
                                                    ⟜usbvideo!_imp_KeReleaseSpinLock
```

`USBVideoFilterClose` calls *PowerDownDevice* which schedules a *WorkItem*:

```
& .\UfSymbol.ps1 -Image $ImageFile -Display usbvideo!PowerDownDevice

usbvideo!PowerDownDevice+0xbe:
488b4918        mov     rcx,qword ptr [rcx+18h]
48ff15f7aa0300  call    qword ptr [usbvideo!_imp_IoAllocateWorkItem (00000001`c00442a8)]
0f1f440000      nop     dword ptr [rax+rax]
488d1533feffff  lea     rdx,[usbvideo!IdleDetectWorkItem (00000001`c00095f0)]
4885c0          test    rax,rax
742b            je      usbvideo!PowerDownDevice+0x105 (00000001`c00097ed)

usbvideo!PowerDownDevice+0xda:
4c8bcb          mov     r9,rbx
488983e8000000  mov     qword ptr [rbx+0E8h],rax
41b801000000    mov     r8d,1
c783d800000001000000 mov dword ptr [rbx+0D8h],1
488bc8          mov     rcx,rax
48ff156aaa0300  call    qword ptr [usbvideo!_imp_IoQueueWorkItem (00000001`c0044250)]
```

`IdleDetectWorkItem` call graph:

```
usbvideo!IdleDetectWorkItem [8]
│                          ⟜usbvideo!_imp_KeAcquireSpinLockRaiseToDpc
│                          ⟜usbvideo!_imp_IoFreeWorkItem
│                          ⟜usbvideo!_imp_KeReleaseSpinLock
└─────────────────────────▷usbvideo!RequestDxPowerIrp
                                                     ⟜usbvideo!_imp_PoRequestPowerIrp
                           ⟜usbvideo!_imp_IoReleaseRemoveLockEx
```

**IRP_MJ_CREATE** call graph:

```
usbvideo!USBVideoFilterCreate [22]
│                            ⟜usbvideo!_imp_KsGetParent
│                            ⟜usbvideo!_imp_ExAllocatePoolWithTag
│                            ⟜usbvideo!_imp_KsAddItemToObjectBag
│                            ⟜usbvideo!_imp_ExFreePoolWithTag
│                            usbvideo!memset
├───────────────────────────▷usbvideo!PowerUpDevice
│                                                  ⟜usbvideo!_imp_KeAcquireSpinLockRaiseToDpc
│                                                  ⟜usbvideo!_imp_KeReleaseSpinLock
│                                                  usbvideo!RequestDxPowerIrp
│                                                  usbvideo!WPP_SF_D
│                            ⟜usbvideo!_imp_KsRemoveItemFromObjectBag
...
                             ⟜usbvideo!_imp_IoCsqInsertIrp
```

Up to this point, we can infer the following:

* CreateFile powers up the device using *(IRP_MN_SET_POWER, PowerDeviceD0)*,
adds the IRP to a *CSQ*.
* CloseHandle schedules a *WorkItem*. The *WorkerRoutine* powers down the device
*(IRP_MN_SET_POWER, PowerDeviceD3)*.

Since user mode receives STATUS_CANCELLED it is implied that somewhere in kernel, an
instruction like `mov eax,0C0000120h` is executed. Looking for matches in the *usbvideo*
reveals no results. Alternatively, there are matches for `mov [rdi+30h],0C0000120h`
representing *Irp&#x2192;IoStatus.Status*, or for `mov edx,0C0000120h` passed as a
2<sup>nd</sup> argument to an internal function.

After a few retries, this stack trace reveals the code path:

```
fffff807`79fbf61a ba200100c0      mov     edx,0C0000120h
fffff807`79fbf61f 488bcb          mov     rcx,rbx
fffff807`79fbf622 e831020000      call    usbvideo!FilterCreateQueue_CompleteQueue (fffff807`79fbf858)

0: kd> k

 # Child-SP          RetAddr               Call Site
00 ffff9104`4401f770 fffff807`79fbf627     usbvideo!FilterCreateQueue_CompleteQueue+0x1a
01 ffff9104`4401f7b0 fffff807`79f98b38     usbvideo!ExitIrpThreadAndQueue+0xc7
02 ffff9104`4401f7f0 fffff807`79f94bf3     usbvideo!StopUSBVideoDevice+0x44
03 ffff9104`4401f820 fffff807`7087b8a7     usbvideo!USBVideoSetPower+0x63
04 ffff9104`4401f860 fffff807`7087b09e     ks!CKsDevice::DispatchDeviceSetPowerIrp+0x35f
05 ffff9104`4401f8c0 fffff807`54da3787     ks!CKsDevice::DispatchPower+0x12e
06 ffff9104`4401f920 fffff807`54cac33d     nt!IopPoHandleIrp+0x3b
07 ffff9104`4401f950 fffff807`54da6c69     nt!IofCallDriver+0x6d
08 ffff9104`4401f990 fffff807`79ec157e     nt!IoCallDriver+0x9
09 ffff9104`4401f9c0 fffff807`79ec1133     ksthunk!CKernelFilterDevice::DispatchIrp+0x25e
0a ffff9104`4401fa20 fffff807`54db1477     ksthunk!CKernelFilterDevice::DispatchIrpBridge+0x13
0b ffff9104`4401fa50 fffff807`54c51425     nt!PopIrpWorker+0x207
0c ffff9104`4401faf0 fffff807`54e24504     nt!PspSystemThreadStartup+0x55
0d ffff9104`4401fb40 00000000`00000000     nt!KiStartSystemThread+0x34

0: kd> !irp @rax

Irp is active with 17 stacks 16 is current (= 0xffffc68925cea558)
 No Mdl: No System Buffer: Thread ffffc689271e7080:  Irp stack trace.
     cmd  flg cl Device   File     Completion-Context

>[IRP_MJ_CREATE(0), N/A(0)]
            0  1 ffffc6891e1813f0 ffffc68927f1c8c0 00000000-00000000    pending
	       \Driver\usbvideo
			Args: ffff9104460574d0 01000060 00000000 00000000
 [IRP_MJ_CREATE(0), N/A(0)]
            0  0 ffffc6891e1ced80 ffffc68927f1c8c0 00000000-00000000
	       \Driver\ksthunk
			Args: ffff9104460574d0 01000060 00000000 00000000
```

And the call graph:

```
StopUSBVideoDevice [43]
├─────────────────▷ExitIrpThreadAndQueue
│                  │                     ⟜_imp_ExFreePoolWithTag
│                  │                     ⟜_imp_IofCompleteRequest
│                  │                     ⟜_imp_IoCsqRemoveNextIrp
│                  ├────────────────────▷FilterCreateQueue_CompleteQueue
│                  │                     └──────────────────────────────▷FilterCreateQueue_CompleteIrp
│                  │                                                     ⟜_imp_IoCsqRemoveNextIrp
│                  │                     ⟜_imp_KeReleaseSemaphore
...
│                                        ⟜_imp_KeWaitForSingleObject
│                                        ⟜_imp_ObfDereferenceObject
└─────────────────▷UnConfigureUSBVideoDevice
                   ├─────────────────────────▷USBVideoCallUSBD
                   │                          │                ⟜_imp_KeInitializeEvent
                   │                          │                ⟜_imp_IoBuildDeviceIoControlRequest
                   │                          │                ⟜_imp_IoSetCompletionRoutineEx
                   │                          │                ⟜_imp_IofCallDriver
                   │                          │                ⟜_imp_KeWaitForSingleObject
...
                   │                                           ⟜_imp_IoCancelIrp
                   │                                           ⟜_imp_IofCompleteRequest
```

---

*StopUSBVideoDevice* calls *ExitIrpThreadAndQueue&#x2192;FilterCreateQueue_CompleteQueue(edx = 0xC0000120h)*.
*FCQ_CQ* dequeues all *IRP*s from the cancel-safe queue and completes them.
