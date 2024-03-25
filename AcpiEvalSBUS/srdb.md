System Management Bus Access through ACPI Methods on Windows
---

Introduction
-

In user mode, there are no built-in APIs to issue SMBUS commands. Both Intel
and AMD packages implement a dedicated function, part of the chipset,
which can drive the electrical protocol.

The function is placed at a fixed BDF: newer Intel uses 0:1F.4, AMD uses 0:14.0.

The SMBUS registers such as *address, command, status, protocol type, start, stop*
are represented in IO port space. Intel does **not document** the wait-state
between *status* reads, while AMD does.

*Some* Intel models expose **ACPI methods** that encapsulate the wait-states.
AMD places the SMBUS controller outside of ACPI.
```
0: kd> !amli u ffffd1099d508c02
ffffd1099d508c02:[\_SB.PCI0.SBUS.STRT]
Store(0xc8, Local0)
While(Local0)
{
|   If(And(HSTS, 0x40, )) ; bit used as semaphore among
                          ; consumers that use the SMBus
                          ; logic
|   {
|   |   Decrement(Local0)
|   |   Sleep(One)
|   |   If(LEqual(Local0, Zero))
|   |   {
|   |   |   Return(One)
|   |   }
|   }
|   Else
|   {
|   |   Store(Zero, Local0)
|   }
}
Store(0xfa0, Local0)
While(Local0)
{
|   If(And(HSTS, One, )) ; a 1 indicates that the PCH is
                         ; running a command from the
                         ; host interface
|   {
|   |   Decrement(Local0)
|   |   Stall(0x32)
|   |   If(LEqual(Local0, Zero))
|   |   {
|   |   |   KILL()
|   |   }
|   }
|   Else
|   {
|   |   Return(Zero)
|   }
}
Return(One)
```
The ACPI method is *evaluated* through a public ioctl. The file name
representing the IO target has to be determined.

Research
-

*ACPI Component Architecture* SDK has samples that extract the ACPI table.
Method evaluation is not part of the source code.

During OS uptime, the device objects call into the driver stack. For example,
Iris gfx issues *\_DOD* method to determine devices attached to it. Every method
invocation by an FDO implementing an embedded controller is
[solved](https://learn.microsoft.com/en-us/windows-hardware/drivers/acpi/device-stacks-for-an-acpi-device) by the ACPI driver underneath: audio, ethernet,
wifi, storage controller, display, bluetooth.

> If an ACPI device is a hardware device integrated into the system board,
> the system creates a device stack with a bus filter device object (filter DO)

Let's place a breakpoint on a candidate: *ACPIIoctlEvalControlMethod*. The
ACPI input buffer is stored at RDX+18. RCX represents the \_DEVICE\_OBJECT.

`bp ACPI!ACPIIoctlEvalControlMethod "db poi(@rdx+18) L10; kn"`
```
ffffba8a`c97888b0  41 65 69 43 5f 44 53 4d-3c 00 00 00 04 00 00 00  AeiC_DSM<.......
 # Child-SP          RetAddr               Call Site
00 ACPI!ACPIIoctlEvalControlMethod
01 ACPI!ACPIIrpDispatchDeviceControl
02 ACPI!ACPIDispatchIrp
03 nt!IofCallDriver
04 Wdf01000!FxIoTarget::Send
05 Wdf01000!FxIoTarget::SubmitSync
06 Wdf01000!FxIoTargetSendIoctl
07 Wdf01000!imp_WdfIoTargetSendIoctlSynchronously
08 USBXHCI!Controller_ExecuteDSM
09 USBXHCI!Controller_QuerySupportedDSMs
0a USBXHCI!Controller_Create
0b USBXHCI!Controller_WdfEvtDeviceAdd
```
In this case, the USB controller FDO calls the *\_DSM* method into the ACPI driver.

The entry points of the filter driver are located in
*\_DEVICE_OBJECT&#8594;\_DRIVER\_OBJECT&#8594;MajorFunction*.

```
2: kd> dt nt!_DEVICE_OBJECT DriverObject @RCX  
   +0x008 DriverObject : 0xffffa902`21b0ed00 _DRIVER_OBJECT

2: kd> dt nt!_DRIVER_OBJECT -a28 MajorFunction 0xffffa902`21b0ed00
   +0x070 MajorFunction : 
    [00] 0xfffff804`f72a1010     long  ACPI!ACPIDispatchIrp+0
...
    [27] 0xfffff804`f72a1010     long  ACPI!ACPIDispatchIrp+0
```
*ACPIDispatchIrp*  handles all IRP_MJ functions, including *IRP\_MJ\_CREATE* at offset 0.
By the time CREATE is called, a name must have been generated. Let's disassemble
AddDevice, placed in DriverExtension field:
```
2: kd> dx ((nt!_DRIVER_OBJECT *)((nt!_DEVICE_OBJECT *)@RCX)->DriverObject)->DriverExtension->AddDevice
0xfffff804f735a7e0 : ACPI!ACPIDispatchAddDevice+0x0 [Type: long (__cdecl*)(_DRIVER_OBJECT *,_DEVICE_OBJECT *)]
    ACPI!ACPIDispatchAddDevice+0x0 [Type: long __cdecl(_DRIVER_OBJECT *,_DEVICE_OBJECT *)]

2: kd> uf ACPI!ACPIDispatchAddDevice
ACPI!ACPIDispatchAddDevice:
488bc4          mov     rax,rsp
...
c744242000010000 mov     dword ptr [rsp+20h],100h
48ff15e86f0600  call    qword ptr [ACPI!_imp_IoCreateDevice (fffff803`306cc1b0)]
...
48ff15c36f0600  call    qword ptr [ACPI!_imp_IoAttachDeviceToDeviceStack (fffff803`306cc1b8)]
...
e8df9d0700      call    ACPI!ACPICreateRootSymbolicLink (fffff803`306df1c4)
...
2: kd> uf ACPI!ACPICreateRootSymbolicLink
No code found, aborting
```
*AddDevice* creates a DO, calls **ACPICreateRootSymbolicLink**. The function is
paged out, so disassembly fails. To solve it, `acpi.sys` is opened as a dump file:
```
Loading Dump File [C:\Windows\System32\drivers\acpi.sys]
uf acpi!ACPICreateRootSymbolicLink:
...
acpi!ACPICreateRootSymbolicLink+0xa7:
488bd3          mov     rdx,rbx
488d4c2430      lea     rcx,[rsp+30h]
48ff15f6d3feff  call    qword ptr [acpi!_imp_RtlInitUnicodeString (00000001`c008c670)]
0f1f440000      nop     dword ptr [rax+rax]
488d542430      lea     rdx,[rsp+30h]
488d0dbd00feff  lea     rcx,[acpi!ACPISymbolicLinkName (00000001`c007f348)]
48ff1586d0feff  call    qword ptr [acpi!_imp_IoCreateSymbolicLink (00000001`c008c318)]
...
0:000> du poi(00000001`c007f348+8)
00000001`c00bab58  "\DosDevices\ACPI_ROOT_OBJECT"
```
This is the name of the PDO representing the root of the ACPI namespace. A
symbolic link is available for *ioctl* access.
```
DECLARE_CONST_UNICODE_STRING(key, L"\\DosDevices\\ACPI_ROOT_OBJECT");

WDF_IO_TARGET_OPEN_PARAMS_INIT_OPEN_BY_NAME(&parms, &key,
    STANDARD_RIGHTS_READ|STANDARD_RIGHTS_WRITE);
status = WdfIoTargetOpen(context->Sbus, &parms);
```
The SMBUS driver does not create a symbolic link, nor a device interface.

ACPI Method Invocation
-
To invoke an ACPI method in the *root* object, an *absolute name* is needed.
The SMBUS controller is located at *&lt;Node1&gt;.&lt;Node2&gt;.**SBUS***,
where Node1 is always *\\\_SB* and Node2 is *PCI0* in many cases. With
*IOCTL_ACPI_ENUM_CHILDREN*, the name is retrieved:
```
acpi = (PACPI_ENUM_CHILDREN_INPUT_BUFFER)context->Acpi;
RtlZeroMemory(acpi, context->Inlen);
acpi->Signature = ACPI_ENUM_CHILDREN_INPUT_BUFFER_SIGNATURE;
acpi->Flags = ENUM_CHILDREN_NAME_IS_FILTER;
acpi->NameLength = 5;
RtlStringCchPrintfA(acpi->Name, acpi->NameLength, "SBUS");

response = (PACPI_ENUM_CHILDREN_OUTPUT_BUFFER)context->Response;
size = context->Outlen;
RtlZeroMemory(response, size);
WDF_MEMORY_DESCRIPTOR_INIT_BUFFER(&indesc, acpi, (ULONG)sizeof(*acpi));
WDF_MEMORY_DESCRIPTOR_INIT_BUFFER(&outdesc, response, (ULONG)size);
status = WdfIoTargetSendInternalIoctlSynchronously(context->Sbus, NULL,
            IOCTL_ACPI_ENUM_CHILDREN, &indesc, &outdesc, NULL, NULL);
if (NT_SUCCESS(status)) {
    child = response->Children;
    RtlCopyMemory(context->Namespace, child->Name, child->NameLength);
}

return status;
```

The SMBUS has several wire protocols: quick command, send/receive byte, write/read
byte/word, write/read block. Accessing the byte transfer method requires *prior
knowledge* about the return value.

With *!amli*, the body is decompiled:
```
2: kd> !amli u ffffd1865f07821a
ffffd1865f07821a:[\_SB.PCI0.SBUS.SRDB]
If(STRT())
{
|   Return(0xffff)
}
Store(Zero, I2CE)
Store(0xbf, HSTS) ; Host Busy(1C) + Interrupt(1C) +
                  ; Device Error(1C) + Bus Error(1C) +
                  ; Failed(1C) + SMBALERT(1C) +
                  ; BYTE_DONE(1C)
Store(Or(Arg0, One, ), TXSA)
Store(Arg1, HCOM)
Store(0x48, HCON) ; Byte Data | Start
If(COMP())
{
|   Or(HSTS, 0xff, HSTS)
|   Return(DAT0)
}
Return(0xffff)
```
The read-byte protocol returns 0xFFFF in case of failure, or a byte value.
The input parameters and the return value are handled:
```
acpi = context->Acpi;
acpi->ArgumentCount = 2;
size = FIELD_OFFSET(ACPI_EVAL_INPUT_BUFFER_COMPLEX_EX, Argument)+
            acpi->ArgumentCount*sizeof(ACPI_METHOD_ARGUMENT);
RtlZeroMemory(acpi, size);

acpi->Signature = ACPI_EVAL_INPUT_BUFFER_COMPLEX_SIGNATURE_EX;
RtlStringCchPrintfA(acpi->MethodName, sizeof(acpi->MethodName), "%s.SRDB", context->Namespace);
acpi->Size = acpi->ArgumentCount*sizeof(ACPI_METHOD_ARGUMENT);

arg = acpi->Argument;
ACPI_METHOD_SET_ARGUMENT_INTEGER(arg, address);
arg = ACPI_METHOD_NEXT_ARGUMENT(acpi->Argument);
ACPI_METHOD_SET_ARGUMENT_INTEGER(arg, command);
WDF_MEMORY_DESCRIPTOR_INIT_BUFFER(&indesc, acpi, size);

size = ACPI_OUTPUT_RAW_LENGTH(1);
response = context->Response;
WDF_MEMORY_DESCRIPTOR_INIT_BUFFER(&outdesc, response, size);

start = KeQueryPerformanceCounter(&frequency);
status = WdfIoTargetSendInternalIoctlSynchronously(context->Sbus, NULL,
            IOCTL_ACPI_EVAL_METHOD_EX, &indesc, &outdesc, NULL, NULL);
if (NT_SUCCESS(status)) {
    stop = KeQueryPerformanceCounter(NULL);
    cookie = response->Argument[0].Argument;

    if (cookie == 0xFFFF) {
        DbgPrintEx(DPFLTR_IHVDRIVER_ID, DPFLTR_TRACE_LEVEL, __FUNCTION__
            " took %I64u us\n", (stop.QuadPart-start.QuadPart)*1000000/frequency.QuadPart);
        return STATUS_DEVICE_DATA_ERROR;
    } else {
        *buffer = (UCHAR)cookie;
    }

}

return status;
```
2 arguments were prepared for the ioctl: *address* and *command*. The *response*
returns the buffer to the application. If the cookie is 0xFFFF, then the protocol
is not recognized by slave or the address is not valid.

Read-word protocol takes an identical approach: the cookie is set to MAXUINT in
case of failure.

For statistical purposes, the call is measured. Failure lasts for 200+ ms, normal
command takes &lt;570 &#x00B5;s.

Read-block protocol returns a buffer in case of success or an integer:
```
2: kd> !amli u ffffd18c8f0789b2
ffffd18c8f0789b2: [\_SB.PCI0.SBUS.SBLR]
Name(TBUF, Buffer(0x100){})
If(STRT())
{
|   Return(Zero)
}
Store(Arg2, I2CE)
Store(Arg1, HCOM)
Store(Or(Arg0, One, ), TXSA)
Store(0x54, HCON)
...
While(LLess(Local1, DerefOf(Index(TBUF, Zero, ))))
{
|   Store(0xfa0, Local0)
|   While(LAnd(LNot(And(HSTS, 0x80, )), Local0))
|   {
|   |   Decrement(Local0)
|   |   Stall(0x32)
|   }
|   If(LNot(Local0))
|   {
|   |   KILL()
|   |   Return(Zero)
|   }
|   Store(HBDR, Index(TBUF, Local1, ))
|   Store(0x80, HSTS)
|   Increment(Local1)
}
If(COMP())
{
|   Or(HSTS, 0xff, HSTS)
|   Return(TBUF)
}
Return(Zero)
```
In case of a persistent failure, *Stall(0x32 &#x00B5;s)* is called 4000 times.

The response *Type* determines if the method completed or failed:
```
cookie = response->Argument[0].Argument;
if (response->Argument[0].Type == ACPI_METHOD_ARGUMENT_INTEGER && !cookie) {
    status = STATUS_DEVICE_DATA_ERROR;
} else {
    RtlCopyMemory(rbytes, response->Argument[0].Data, sizeof(*rbytes));
    if (count > *rbytes) {
        count = *rbytes;
    }
    RtlCopyMemory(buffer, 1+(PUCHAR)response->Argument[0].Data, count);
}
```
A client for ACPI SMBUS methods can implement a table of known wrappers on top
of *IOCTL\_ACPI\_EVAL\_METHOD\_EX*. At runtime, the wrappers are tested using a
passive device like *SMBUS\_SMART\_BATTERY\_ADDRESS*. The device responds to
read-word protocol or returns a value out of range. Both cases indicate that the
method is present and a proper slave device can be adressed.
```
const SMBUS_FUNCTION SmbusIntelFunction[] = {
    {
        { 6, 58 },
        {
            'BDRS',
            SmbusIntel_6_58_SRDB
        },
        {
            'WDRS',
            SmbusIntel_6_58_SRDW
        },
        {
            'RLBS',
            SmbusIntel_6_58_SBLR
        },
    }
};

#define SMBUS_SMART_BATTERY_ADDRESS 0b0001011

const UCHAR defaddr = SMBUS_SMART_BATTERY_ADDRESS << 1;
UCHAR testb[0x100];
BOOLEAN i2ce = FALSE;

if (context->Cpuinfo.Vendor == VENDOR_INTEL) {
    for (i = 0; i < sizeof(SmbusIntelFunction)/sizeof(SmbusIntelFunction[0]); i ++) {
        sfe = &SmbusIntelFunction[i];

        if (context->Cpuinfo.Family != sfe->Cpuinfo.Family ||
            context->Cpuinfo.Model != sfe->Cpuinfo.Model) {
            continue;
        }

        Mebyte = sfe->AcpiReadByte.Method;
        if (Mebyte) {
            ASSERT(sfe->AcpiReadByte.Name);

            status = Mebyte(context, defaddr, 0, &test);
            if (NT_SUCCESS(status) || STATUS_DEVICE_DATA_ERROR == status) {
                context->AcpiReadByte = Mebyte;
            }
        }

        Meword = sfe->AcpiReadWord.Method;
        if (Meword) {
            ASSERT(sfe->AcpiReadWord.Name);

            status = Meword(context, defaddr, 0, &testw);
            if (NT_SUCCESS(status) || STATUS_DEVICE_DATA_ERROR == status) {
                context->AcpiReadWord = Meword;
            }
        }

        Meblock = sfe->AcpiReadBlock.Method;
        if (Meblock) {
            ASSERT(sfe->AcpiReadBlock.Method);

            status = Meblock(context, defaddr, 0, i2ce, testb, sizeof(testb), &rbytes);
            if (NT_SUCCESS(status) || STATUS_DEVICE_DATA_ERROR == status) {
                context->AcpiReadBlock = Meblock;
            }
        }
    }
}
```
Note: for each EVAL ioctl, the OS creates a watchdog timer that expires in 30
seconds; it *does overreact*.

Synchronization
-

The *STRT* method polls bit 6 on *HSTS* as long as there is a consumer, using 
a *Sleep(1ms)*. The specification
[states](https://uefi.org/specs/ACPI/6.5/05_ACPI_Software_Programming_Model.html#control-method-execution):

> Interpretation of a Control Method is not preemptive, but it can block. When
> a control method does block, OSPM can initiate or continue the execution of
> a different control method. A control method can only assume that access to
> global objects is exclusive for any period the control method does not block.

The operating regions are exclusive by [design](https://uefi.org/specs/ACPI/6.5/05_ACPI_Software_Programming_Model.html#access-to-operation-regions).

  > Control methods must have exclusive access to any address accessed via fields
  > declared in Operation Regions.

```
| OpRegion(SMBI:RegionSpace=SystemIO,Offset=0xf040,Len=16)
| Field(:Base=SMBI,BaseObjData=ffffd1099d507078)
| * Base =>OpRegion(:RegionSpace=SystemIO,Offset=0xf040,Len=16)
| FieldUnit(HSTS:FieldParent=ffffd1099d5070e8,ByteOffset=0x0,
            StartBit=0x0,NumBits=8,FieldFlags=0x1)
| FieldUnit(:FieldParent=ffffd1099d5070e8,ByteOffset=0x1,
            StartBit=0x0,NumBits=8,FieldFlags=0x1)
| FieldUnit(HCON:FieldParent=ffffd1099d5070e8,ByteOffset=0x2,
            StartBit=0x0,NumBits=8,FieldFlags=0x1)
| FieldUnit(HCOM:FieldParent=ffffd1099d5070e8,ByteOffset=0x3,
            StartBit=0x0,NumBits=8,FieldFlags=0x1)
| FieldUnit(TXSA:FieldParent=ffffd1099d5070e8,ByteOffset=0x4,
            StartBit=0x0,NumBits=8,FieldFlags=0x1)
| FieldUnit(DAT0:FieldParent=ffffd1099d5070e8,ByteOffset=0x5,
            StartBit=0x0,NumBits=8,FieldFlags=0x1)
| FieldUnit(DAT1:FieldParent=ffffd1099d5070e8,ByteOffset=0x6,
            StartBit=0x0,NumBits=8,FieldFlags=0x1)
| FieldUnit(HBDR:FieldParent=ffffd1099d5070e8,ByteOffset=0x7,
            StartBit=0x0,NumBits=8,FieldFlags=0x1)
| FieldUnit(PECR:FieldParent=ffffd1099d5070e8,ByteOffset=0x8,
            StartBit=0x0,NumBits=8,FieldFlags=0x1)
| FieldUnit(RXSA:FieldParent=ffffd1099d5070e8,ByteOffset=0x9,
            StartBit=0x0,NumBits=8,FieldFlags=0x1)
| FieldUnit(SDAT:FieldParent=ffffd1099d5070e8,ByteOffset=0xa,
            StartBit=0x0,NumBits=16,FieldFlags=0x1)
```

As long as there are no errors and no contention, the method is executed with
full control. For comparison, *Linux kernel* and *ReactOS* acquire an interpreter
lock with each method invocation. The lock is released and acquired when calling
*Sleep*. *Stall* does not relinquish the thread.

Data Gathering
-
The ACPI bitmap is preserved in *Memory.DMP* generated with a BSOD. The files
can be processed with *KD.exe* using JavaScript:
```
"use strict";

function toString(s)
{
    if (typeof s == "string") {
        return s;
    }
    var m = ""
    for (var i of s) {
        m += i + "\n";
    }
    return m;
}

function invokeScript()
{
    var ctl = host.namespace.Debugger.Utility.Control;
    var devext = new Array();
    var amli = new Array();

    var output = ctl.ExecuteCommand("!pcitree");

    for (var line of output) {
        if (line.match("Serial Bus Controller/Unknown Sub Class")) {
            var dbgcli = "!devext " + line.split(" devext ")[1].split(" ")[0];
            var dout = ctl.ExecuteCommand(dbgcli);
            if (!dout[0].match("PDO Extension, Bus 0x0,")) {
                continue;
            }
            devext.push(toString(dout));
        }
    }

    output = ctl.ExecuteCommand("!amli find SBUS");
    for (var line of output) {
        if (line.trim() == "") {
            continue;
        }
        var dout = ctl.ExecuteCommand("!amli dns /s " + line);
        amli.push(toString(dout));
    }

    output = ctl.ExecuteCommand("!sysinfo cpuinfo");
    var cpuinfo = output[4] + "\n" + output[5];
    var j = JSON.stringify({
        devext: devext,
        amli: amli,
        cpuinfo: cpuinfo
    });
    host.diagnostics.debugLog(j);
}
```
The script centers on *!amli find SBUS* and uses *!sysinfo cpuinfo* to gather
adjacent data about the model. If there are other SMBUS devices, their BDF is
printed using *!pcitree*.

Of 11 Intel systems, 7 Xeon and 4 Core, only 2 Core SKUs implement the full
range of SMBUS transfer types as ACPI methods.

Conclusion
-
* Typical consumers of ACPI are ECs whose FDOs lie on top of ACPI filter.
* Remote clients can invoke SMBUS ACPI methods after opening a root object name
  and computing the absolute path. The method is decompiled, input arguments and
  return value are part of *IOCTL\_ACPI\_EVAL\_METHOD\_EX*.
* SMBUS can be accessed either with ACPI methods or with IO ports. IO ports
  implementation can gather a baseline from different platforms and specify
  the largest wait-state. The host controller supports up to 100 kHz clock speed.
  An algorithm can be easily approached through electrical engineering.
* Applications cannot access directly the root object.
  *IRP\_MJ\_DEVICE\_CONTROL* is handled differently than *IRP\_MJ\_INTERNAL\_DEVICE\_CONTROL*.
