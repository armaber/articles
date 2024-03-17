System Management Bus Access through ACPI Methods on Windows
---

Introduction
-

In user mode, there are no built-in APIs to issue SMBUS commands. Both Intel
and AMD processor package allocates a dedicated function, part of the chipset,
which can drive the electrical protocol.

The function is placed at a fixed BDF: newer Intel uses 0:1F.4, AMD uses 0:14.0.

The SMBUS registers such as *address, command, status, protocol type, start, stop*
are represented in IO Port space. Intel does **not document** the wait-state
between *status* reads, while AMD does document it.

*Some* Intel models expose **ACPI methods** that encapsulate the wait-states.
AMD places the SMBUS controller outside of ACPI.
```
0: kd> !amli u ffffd1099d508c02
ffffd1099d508c02:[\_SB.PCI0.SBUS.STRT]
Store(0xc8, Local0)
While(Local0)
{
|   If(And(HSTS, 0x40, ))
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
|   If(And(HSTS, One, ))
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

During OS uptime, the device objects call into the driver stack. Iris gfx issues
*\_DOD* method to determine devices attached to it. Every method invocation by an FDO
implementing an embedded controller is
[solved](https://learn.microsoft.com/en-us/windows-hardware/drivers/acpi/device-stacks-for-an-acpi-device)
by the ACPI driver underneath.
> If an ACPI device is a hardware device integrated into the system board,
> the system creates a device stack with a bus filter device object (filter DO)

Let's place a breakpoint on a candidate: *ACPIIoctlEvalControlMethod*. The
ACPI input buffer is stored at RDX+18. RCX represents the _DEVICE_OBJECT.

`bp ACPI!ACPIIoctlEvalControlMethod "db poi(@rdx+18) L10; kn"`
~~~
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
~~~

The USB controller FDO calls the *_DSM* method into the ACPI driver.
> This optional object is a control method that enables devices to provide device
> specific control functions that are consumed by the device driver.

The entry points of the filter driver are located in
*_DEVICE_OBJECT->_DRIVER_OBJECT->MajorFunction*.

~~~
2: kd> dx ((nt!_DRIVER_OBJECT *)((nt!_DEVICE_OBJECT *)@RCX)->DriverObject)->MajorFunction
    [0]  : 0xfffff80774d71010 : ACPI!ACPIDispatchIrp+0x0 [Type: long (__cdecl*)(_DEVICE_OBJECT *,_IRP *)]
...
    [27] : 0xfffff80774d71010 : ACPI!ACPIDispatchIrp+0x0 [Type: long (__cdecl*)(_DEVICE_OBJECT *,_IRP *)]
~~~

The driver uses one entry point that handles all IRP_MJ functions, including
IRP_MJ_CREATE at offset 0. By the time MJ_CREATE is called, a name must have
been generated. Let's disassemble AddDevice, placed in DriverExtension field:
~~~
2: kd> dx ((nt!_DRIVER_OBJECT *)((nt!_DEVICE_OBJECT *)@RCX)->DriverObject)->DriverExtension->AddDevice
0xfffff80330665100 : ACPI!ACPIDispatchAddDevice+0x0 [Type: long (__cdecl*)(_DRIVER_OBJECT *,_DEVICE_OBJECT *)]
    ACPI!ACPIDispatchAddDevice+0x0 [Type: long __cdecl(_DRIVER_OBJECT *,_DEVICE_OBJECT *)]

2: kd> uf ACPI!ACPIDispatchAddDevice
ACPI!ACPIDispatchAddDevice:
fffff803`30665100 488bc4          mov     rax,rsp
...
fffff803`306651b9 c744242000010000 mov     dword ptr [rsp+20h],100h
fffff803`306651c1 48ff15e86f0600  call    qword ptr [ACPI!_imp_IoCreateDevice (fffff803`306cc1b0)]
...
fffff803`306651ee 48ff15c36f0600  call    qword ptr [ACPI!_imp_IoAttachDeviceToDeviceStack (fffff803`306cc1b8)]
...
fffff803`306653e0 e8df9d0700      call    ACPI!ACPICreateRootSymbolicLink (fffff803`306df1c4)
...
2: kd> uf ACPI!ACPICreateRootSymbolicLink
No code found, aborting
~~~
*AddDevice* creates a DO, calls **ACPICreateRootSymbolicLink**. The function is
paged out, so disassembly fails. To solve it, `acpi.sys` is opened as a dump file:
~~~
Loading Dump File [C:\Windows\System32\drivers\acpi.sys]
uf acpi!ACPICreateRootSymbolicLink:
...
acpi!ACPICreateRootSymbolicLink+0xa7:
00000001`c009f26b 488bd3          mov     rdx,rbx
00000001`c009f26e 488d4c2430      lea     rcx,[rsp+30h]
00000001`c009f273 48ff15f6d3feff  call    qword ptr [acpi!_imp_RtlInitUnicodeString (00000001`c008c670)]
00000001`c009f27a 0f1f440000      nop     dword ptr [rax+rax]
00000001`c009f27f 488d542430      lea     rdx,[rsp+30h]
00000001`c009f284 488d0dbd00feff  lea     rcx,[acpi!ACPISymbolicLinkName (00000001`c007f348)]
00000001`c009f28b 48ff1586d0feff  call    qword ptr [acpi!_imp_IoCreateSymbolicLink (00000001`c008c318)]
...
0:000> du poi(00000001`c007f348+8)
00000001`c00bab58  "\DosDevices\ACPI_ROOT_OBJECT"
~~~
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
where Node1 is always *\_SB* and Node2 is *PCI0* in many cases. With
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
Store(0xbf, HSTS)
Store(Or(Arg0, One, ), TXSA)
Store(Arg1, HCOM)
Store(0x48, HCON)
If(COMP())
{
|   Or(HSTS, 0xff, HSTS)
|   Return(DAT0)
}
Return(0xffff)
```
The read-byte protocol returns *0xFFFF* in case of failure, or a byte value.
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

Read-word protocol takes an identical approach: the cookie is set to MAX_UINT
in case of failure.

For statistical purposes, the call is measured. Failure lasts for 200+
miliseconds, normal command takes &lt;570 &#x00B5;s.

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
A client for ACPI SMBUS methods can implement a table of known wrappers
for *IOCTL_ACPI_EVAL_METHOD_EX*. At runtime, the wrappers are tested on a
passive device like *SMBUS_SMART_BATTERY_ADDRESS*. The battery responds to
read-word protocol or returns a value out of range. Both cases indicate
that the method is present and a proper slave device can be adressed.
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
                context->AcpiReadByte = Method;
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

            status = Meblock(context, defaddr, 0, 0, testb, sizeof(testb), &rbytes);
            if (NT_SUCCESS(status) || STATUS_DEVICE_DATA_ERROR == status) {
                context->AcpiReadBlock = Meblock;
            }
        }
    }
}
```

*Note:* for each *EVAL* ioctl, the OS creates a watchdog timer that expires
in 30 seconds; it *does overreact*.

Statistics
-
The ACPI bitmap is preserved in *Memory.DMP* generated with a BSOD. The files
can be processed with *KD.exe* using JavaScript:
~~~
"use strict";

function dumpBlock(b)
{
    if (typeof b == "string") {
        host.diagnostics.debugLog("\"",b, "\",\n");
        return;
    }
    for (var line of b) {
        host.diagnostics.debugLog("\"",line, "\",\n");
    }
}

function invokeScript()
{
    var ctl = host.namespace.Debugger.Utility.Control;
    var output = host.namespace.Debugger.Sessions[0];
    var count = host.namespace.Debugger.Sessions.Count()-1;

    host.diagnostics.debugLog("{\n\"session\": \"", host.namespace.Debugger.Sessions[count], "\",\n");
    output = ctl.ExecuteCommand("!pcitree");

    for (var line of output) {
        if (line.match("Serial Bus Controller/Unknown Sub Class")) {
            host.diagnostics.debugLog("\"devext\": [\n")
            var devext = "!devext " + line.split(" devext ")[1].split(" ")[0];
            host.diagnostics.debugLog("\"",line.trim(),"\",\n");
            dumpBlock(devext);
            var dout = ctl.ExecuteCommand(devext);
            if (!dout[0].match("PDO Extension, Bus 0x0,")) {
                host.diagnostics.debugLog("],\n");
                continue;
            }
            dumpBlock(dout);
            host.diagnostics.debugLog("\"\"],\n");
        }
    }

    output = ctl.ExecuteCommand("!amli find SBUS");
    for (var line of output) {
        if (line.trim() == "") {
            continue;
        }
        host.diagnostics.debugLog("\"amli\": [");
        var dout = ctl.ExecuteCommand("!amli dns /s " + line);
        dumpBlock(dout);
        host.diagnostics.debugLog("\"\"],\n");
    }

    output = ctl.ExecuteCommand("!sysinfo cpuinfo");
    host.diagnostics.debugLog("\"cpuinfo\": [\"", output[4], "\", \n    \"", output[5], "\"]\n} \n");
}
~~~
The script centers on *!amli find SBUS* and uses *!sysinfo cpuinfo* to
gather adjacent data about the model. If there are other SMBUS devices,
their BDF is printed using *!pcitree*.

Of 11 Intel systems, 7 Xeon and 4 Core, only 2 Core SKUs implement the full
range of SMBUS transfer types as ACPI methods.

Conclusion
-
* SMBUS can be accessed either with ACPI methods or with IO ports. IO ports
  implementation can gather a baseline from different platforms and specify
  the largest wait-state.
* Typical consumers of ACPI are ECs whose FDOs are on top of ACPI.
* Remote clients can invoke SMBUS ACPI methods after opening a root object name
  and computing the absolute path. The method is decompiled, input arguments and
  return value are part of *IOCTL_ACPI_EVAL_METHOD_EX*.
* Applications cannot access directly the root object.
  *IRP_MJ_DEVICE_CONTROL* is handled differently than *IRP_MJ_INTERNAL_DEVICE_CONTROL*.