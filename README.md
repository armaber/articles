The articles are written as lightweight lunch discussions, with emphasys on accesibility.
To some degree, one has to be versed in techology and focus on what is relevant.

Many of the topics dive into Windows, as an OS: infrastructure, kernel, features,
or tools.

I am committed to the fitness of an idea being presented. Write an e-mail to point out
gaps. Configuration, administrative tasks are crafted at speed, subject to improvements.
Testing or tedious confirmations are mostly unmentioned. I find it less than ideal if
you, as developer, encounter a showstopper, by going with the flow.

Topics:
- [NtQueryTimerResolution](./NtQueryTimerResolution/usleep.md): thread quantum is not
constant on Windows, applications adjust it at will.
- [SRDB](./AcpiEvalSBUS/srdb.md): Intel PCH contains ACPI methods that can drive
  SMBUS wire protocol.
- [PCITree](./PCITree/brief.md): mentions on PCIe scripted enumeration on Windows.
- [NativeHotPlug](./PCIeHP/notes.md): Windows and ACPI support for PCIe hot plug.
- [HeavyDutyUF](./HDUF/brief.md): disassemble the kernel to build a call tree for a
chosen symbol.
- [IoDecode](./IoDecode/brief.md): decode CTL_CODE values from command line.
- [PciFilter](https://github.com/armaber/drivers/tree/main/PciFilter#readme): observe system
calls below FDOs on PCI eXpress.
- [KsCategory](./KsCategory/cancelled.md): CloseHandle for KSCATEGORY_VIDEO_CAMERA is
multiplexed in kernel mode.

Preparation:
- [IFR](./KmdfLogging/notes.md): enable KMDF logs for analysis.