# Hardware-accelerated GPU scheduling. The switch is HwSchMode (2 = on, 1 = off) under
# GraphicsDrivers, but the value alone does not say whether the graphics driver supports it: on a
# driver without support Windows ignores it, and a plain registry tweak would report a change that
# never happens. So support is asked to the graphics kernel (D3DKMTQueryAdapterInfo with
# KMTQAITYPE_WDDM_2_7_CAPS, whose first bit is HwSchSupported) and without it the tweak is
# not-present. Windows reads the value at boot: a restart is needed.

function Get-GamingHagsActionHelperValue {
    param()
    [pscustomobject]@{ path = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; name = 'HwSchMode' }
}

function Get-GamingHagsActionHelperTweak {
    param([Parameter(Mandatory)]$Tweak)
    $value = Get-GamingHagsActionHelperValue
    [pscustomobject]@{ id = $Tweak.id; set = [pscustomobject]@{ path = $value.path; name = $value.name; kind = 'DWord'; value = $null } }
}

function Get-GamingHagsActionHelperCapability {
    param()
    # One number per graphics adapter: the WDDM 2.7 capability bits, or -1 when the adapter does not
    # answer the query (a driver older than WDDM 2.7). Only reads; nothing is changed.
    if (-not ('WindowsTuneupGpuScheduling' -as [type])) {
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
    const int Wddm27Caps = 70;
    public static int[] Query() {
        EnumAdapters2 list = new EnumAdapters2();
        int status = D3DKMTEnumAdapters2(ref list);
        if (status != 0) throw new InvalidOperationException("D3DKMTEnumAdapters2 failed with status 0x" + status.ToString("X8"));
        if (list.Count == 0) return new int[0];
        int size = Marshal.SizeOf(typeof(AdapterInfo));
        list.Adapters = Marshal.AllocHGlobal(size * (int)list.Count);
        IntPtr caps = Marshal.AllocHGlobal(4);
        try {
            status = D3DKMTEnumAdapters2(ref list);
            if (status != 0) throw new InvalidOperationException("D3DKMTEnumAdapters2 failed with status 0x" + status.ToString("X8"));
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
    [WindowsTuneupGpuScheduling]::Query()
}

function Test-GamingHagsActionHelperSupported {
    param()
    # With a hybrid GPU the setting is global: one adapter with support is enough.
    @(Get-GamingHagsActionHelperCapability | Where-Object { $_ -ge 0 -and ($_ -band 1) }).Count -gt 0
}

function Get-GamingHagsActionState {
    param([Parameter(Mandatory)]$Tweak)
    $state = Get-RegistryTweakState -Tweak (Get-GamingHagsActionHelperTweak -Tweak $Tweak)
    $state | Add-Member -NotePropertyName supported -NotePropertyValue ([bool](Test-GamingHagsActionHelperSupported)) -PassThru
}

function Test-GamingHagsActionState {
    param([Parameter(Mandatory)]$Tweak)
    $state = Get-GamingHagsActionState -Tweak $Tweak
    if (-not $state.supported) { return 'not-present' }
    if ($state.exists -and $state.kind -eq 'DWord' -and [long]$state.value -eq 2) { return 'applied' }
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
    Restore-RegistryTweakState -Tweak (Get-GamingHagsActionHelperTweak -Tweak $Tweak) -State $State
    New-TuneupOutcome -RebootRequired
}
