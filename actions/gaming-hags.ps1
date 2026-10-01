# Hardware-accelerated GPU scheduling. The switch is HwSchMode (2 = on, 1 = off) under
# GraphicsDrivers, but the value alone does not say whether the graphics driver supports it: on a
# driver without support Windows ignores it, and a plain registry tweak would report a change that
# never happens. So support is asked to the graphics kernel (D3DKMTQueryAdapterInfo with
# KMTQAITYPE_WDDM_2_7_CAPS, whose bits are HwSchSupported, HwSchEnabled and HwSchEnabledByDefault)
# and without it the tweak is not-present. Without HwSchMode the driver decides: it counts as on when
# the driver turns it on by default or says that it is on now. Windows reads the value at boot: a
# restart is needed, and an undo asks for one only when it changes the value.

function Get-GamingHagsActionHelperValue {
    param()
    [pscustomobject]@{ path = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; name = 'HwSchMode' }
}

function Get-GamingHagsActionHelperTweak {
    param([Parameter(Mandatory)]$Tweak)
    $value = Get-GamingHagsActionHelperValue
    [pscustomobject]@{ id = $Tweak.id; set = [pscustomobject]@{ path = $value.path; name = $value.name; kind = 'DWord'; value = $null } }
}

function Initialize-GamingHagsActionHelperNative {
    param()
    if ('WindowsTuneupGpuScheduling' -as [type]) { return }
    Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class WindowsTuneupGpuScheduling {
    [StructLayout(LayoutKind.Sequential)]
    struct AdapterInfo { public uint Handle; public uint LuidLow; public int LuidHigh; public uint Sources; public int Precise; }
    [StructLayout(LayoutKind.Sequential)]
    struct EnumAdapters2 { public uint Count; public IntPtr Adapters; }
    [StructLayout(LayoutKind.Sequential)]
    struct QueryAdapterInfo { public uint Handle; public int Type; public IntPtr Data; public uint Size; }
    [StructLayout(LayoutKind.Sequential)]
    struct CloseAdapter { public uint Handle; }
    [DllImport("gdi32.dll")] static extern int D3DKMTEnumAdapters2(ref EnumAdapters2 data);
    [DllImport("gdi32.dll")] static extern int D3DKMTQueryAdapterInfo(ref QueryAdapterInfo data);
    [DllImport("gdi32.dll")] static extern int D3DKMTCloseAdapter(ref CloseAdapter data);
    public const int Wddm27Caps = 70;
    public const int BufferTooSmall = unchecked((int)0xC0000023);
    public static int[] Sizes() {
        return new int[] { Marshal.SizeOf(typeof(AdapterInfo)), Marshal.SizeOf(typeof(EnumAdapters2)), Marshal.SizeOf(typeof(QueryAdapterInfo)), Marshal.SizeOf(typeof(CloseAdapter)) };
    }
    public static int[] Query() {
        int size = Marshal.SizeOf(typeof(AdapterInfo));
        EnumAdapters2 list = new EnumAdapters2();
        // The first call gives the number of adapters, the second fills them. An adapter that
        // appears in between makes the second call answer STATUS_BUFFER_TOO_SMALL: count again once.
        for (int attempt = 0; ; attempt++) {
            list.Adapters = IntPtr.Zero;
            int status = D3DKMTEnumAdapters2(ref list);
            if (status != 0) throw new InvalidOperationException("D3DKMTEnumAdapters2 failed with status 0x" + status.ToString("X8"));
            if (list.Count == 0) return new int[0];
            list.Adapters = Marshal.AllocHGlobal(size * (int)list.Count);
            status = D3DKMTEnumAdapters2(ref list);
            if (status == 0) break;
            Marshal.FreeHGlobal(list.Adapters);
            if (status != BufferTooSmall || attempt > 0) throw new InvalidOperationException("D3DKMTEnumAdapters2 failed with status 0x" + status.ToString("X8"));
        }
        IntPtr caps = Marshal.AllocHGlobal(4);
        try {
            int[] result = new int[list.Count];
            for (int i = 0; i < list.Count; i++) {
                AdapterInfo adapter = (AdapterInfo)Marshal.PtrToStructure(new IntPtr(list.Adapters.ToInt64() + i * size), typeof(AdapterInfo));
                Marshal.WriteInt32(caps, 0);
                QueryAdapterInfo query = new QueryAdapterInfo();
                query.Handle = adapter.Handle;
                query.Type = Wddm27Caps;
                query.Data = caps;
                query.Size = 4;
                result[i] = D3DKMTQueryAdapterInfo(ref query) == 0 ? Marshal.ReadInt32(caps) : -1;
                CloseAdapter close = new CloseAdapter();
                close.Handle = adapter.Handle;
                D3DKMTCloseAdapter(ref close);
            }
            return result;
        } finally {
            Marshal.FreeHGlobal(caps);
            Marshal.FreeHGlobal(list.Adapters);
        }
    }
}
'@
}

function Get-GamingHagsActionHelperCapability {
    param()
    # One number per graphics adapter: the WDDM 2.7 capability bits, or -1 when the adapter does not
    # answer the query (a driver older than WDDM 2.7). Only reads; nothing is changed.
    Initialize-GamingHagsActionHelperNative
    [WindowsTuneupGpuScheduling]::Query()
}

function Get-GamingHagsActionHelperSupportedCapability {
    param()
    # The capability bits of the adapters that support it (bit 0, HwSchSupported). With a hybrid GPU
    # the setting is global: one adapter with support is enough.
    @(Get-GamingHagsActionHelperCapability | Where-Object { $_ -ge 0 -and ($_ -band 1) })
}

function Test-GamingHagsActionHelperSupported {
    param()
    @(Get-GamingHagsActionHelperSupportedCapability).Count -gt 0
}

function Get-GamingHagsActionState {
    param([Parameter(Mandatory)]$Tweak)
    $state = Get-RegistryTweakState -Tweak (Get-GamingHagsActionHelperTweak -Tweak $Tweak)
    $caps = @(Get-GamingHagsActionHelperSupportedCapability)
    # HwSchEnabled (bit 1) or HwSchEnabledByDefault (bit 2) of an adapter that supports it.
    $driverOn = @($caps | Where-Object { $_ -band 6 }).Count -gt 0
    $state | Add-Member -NotePropertyName supported -NotePropertyValue ($caps.Count -gt 0)
    $state | Add-Member -NotePropertyName driverOn -NotePropertyValue $driverOn -PassThru
}

function Test-GamingHagsActionState {
    param([Parameter(Mandatory)]$Tweak)
    $state = Get-GamingHagsActionState -Tweak $Tweak
    if (-not $state.supported) { return 'not-present' }
    if ($state.exists) {
        if ($state.kind -eq 'DWord' -and [long]$state.value -eq 2) { return 'applied' }
        return 'not-applied'
    }
    # Without HwSchMode the driver decides.
    if ($state.driverOn) { return 'applied' }
    'not-applied'
}

function Set-GamingHagsActionDesired {
    param([Parameter(Mandatory)]$Tweak)
    if (-not (Test-GamingHagsActionHelperSupported)) {
        throw 'No graphics adapter supports hardware-accelerated GPU scheduling; nothing was changed'
    }
    $target = (Get-GamingHagsActionHelperTweak -Tweak $Tweak).set
    Write-TuneupRegistryValue -Path $target.path -Name $target.name -Kind 'DWord' -Value 2
    New-TuneupOutcome -RebootRequired
}

function Restore-GamingHagsActionState {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$State)
    $target = Get-GamingHagsActionHelperTweak -Tweak $Tweak
    $before = Get-RegistryTweakState -Tweak $target
    Restore-RegistryTweakState -Tweak $target -State $State
    # Windows reads the value at boot: a restart only matters when the undo changed it.
    $changed = ([bool]$before.exists -ne [bool]$State.exists) -or
        ($before.exists -and ($before.kind -ne $State.kind -or -not (Test-TuneupRegistryValueEqual -Kind $before.kind -Current $before.value -Desired $State.value)))
    if ($changed) { New-TuneupOutcome -RebootRequired }
}
