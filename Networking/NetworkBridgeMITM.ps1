# ============================================================================
# Network Bridge MITM Tool - IMPROVED VERSION with Interface Detection
# Professional UI Design
# ============================================================================

param(
    [string]$ProjectName = "NetworkBridge",
    [string]$BaseDir = "."
)

$ErrorActionPreference = "Stop"

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Network Bridge - Professional Edition" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

$projectRoot = Join-Path $BaseDir $ProjectName
New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
Set-Location $projectRoot

# Create directory structure
Write-Host "`n[1/8] Creating directory structure..." -ForegroundColor Green

$dirs = @(
    "src/$ProjectName.Models",
    "src/$ProjectName.Core/Interfaces",
    "src/$ProjectName.Core/Services",
    "src/$ProjectName.UI/Views",
    "src/$ProjectName.UI/ViewModels",
    "src/$ProjectName.UI/Controls",
    "lib/WinDivert",
    "docs"
)

foreach ($dir in $dirs) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

dotnet new sln --name $ProjectName --force | Out-Null

# ============================================================================
# MODELS PROJECT
# ============================================================================

$modelsDir = "src/$ProjectName.Models"
$modelsCsproj = @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
  </PropertyGroup>
</Project>
"@

$modelsCsproj | Out-File "./$modelsDir/$ProjectName.Models.csproj" -Encoding UTF8

# PhysicalNetworkInterface.cs - NEW
$physicalInterfaceCs = @'
using System;
using System.ComponentModel;
using System.Net.NetworkInformation;
using System.Runtime.CompilerServices;

namespace NetworkBridge.Models
{
    /// <summary>
    /// Represents a physical network interface detected on the system
    /// </summary>
    public class PhysicalNetworkInterface : INotifyPropertyChanged
    {
        private bool _isSelected;

        public string Id { get; set; }
        public string Name { get; set; }
        public string Description { get; set; }
        public NetworkInterfaceType InterfaceType { get; set; }
        public OperationalStatus Status { get; set; }
        public long Speed { get; set; }
        public string MacAddress { get; set; }
        public string IpAddress { get; set; }
        public bool IsPhysical { get; set; }

        public bool IsSelected
        {
            get => _isSelected;
            set { _isSelected = value; OnPropertyChanged(); }
        }

        public string SpeedDisplay => Speed > 0 ? $"{Speed / 1_000_000} Mbps" : "Unknown";
        public string StatusDisplay => Status.ToString();
        public string TypeDisplay => InterfaceType.ToString();

        public event PropertyChangedEventHandler PropertyChanged;

        protected virtual void OnPropertyChanged([CallerMemberName] string propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }
}
'@

$physicalInterfaceCs | Out-File "./$modelsDir/PhysicalNetworkInterface.cs" -Encoding UTF8

# VirtualInterface.cs - UPDATED
$virtualInterfaceCs = @'
using System;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace NetworkBridge.Models
{
    public class VirtualInterface : INotifyPropertyChanged
    {
        private string _name;
        private Guid _id;
        private InterfaceDirection _direction;
        private bool _isActive;
        private string _filter;
        private long _bytesReceived;
        private long _bytesSent;
        private long _packetsReceived;
        private long _packetsSent;

        public Guid Id
        {
            get => _id;
            set { _id = value; OnPropertyChanged(); }
        }

        public string Name
        {
            get => _name;
            set { _name = value; OnPropertyChanged(); }
        }

        public InterfaceDirection Direction
        {
            get => _direction;
            set { _direction = value; OnPropertyChanged(); }
        }

        public bool IsActive
        {
            get => _isActive;
            set { _isActive = value; OnPropertyChanged(); }
        }

        public string Filter
        {
            get => _filter;
            set { _filter = value; OnPropertyChanged(); }
        }

        public long BytesReceived
        {
            get => _bytesReceived;
            set { _bytesReceived = value; OnPropertyChanged(); OnPropertyChanged(nameof(BytesReceivedDisplay)); }
        }

        public long BytesSent
        {
            get => _bytesSent;
            set { _bytesSent = value; OnPropertyChanged(); OnPropertyChanged(nameof(BytesSentDisplay)); }
        }

        public long PacketsReceived
        {
            get => _packetsReceived;
            set { _packetsReceived = value; OnPropertyChanged(); }
        }

        public long PacketsSent
        {
            get => _packetsSent;
            set { _packetsSent = value; OnPropertyChanged(); }
        }

        public string BytesReceivedDisplay => FormatBytes(BytesReceived);
        public string BytesSentDisplay => FormatBytes(BytesSent);
        public string StatusDisplay => IsActive ? "Active" : "Stopped";

        private string FormatBytes(long bytes)
        {
            string[] sizes = { "B", "KB", "MB", "GB" };
            double len = bytes;
            int order = 0;
            while (len >= 1024 && order < sizes.Length - 1)
            {
                order++;
                len = len / 1024;
            }
            return $"{len:0.##} {sizes[order]}";
        }

        public event PropertyChangedEventHandler PropertyChanged;

        protected virtual void OnPropertyChanged([CallerMemberName] string propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }

    public enum InterfaceDirection
    {
        Input,
        Output,
        Bidirectional
    }
}
'@

$physicalInterfaceCs | Out-File "./$modelsDir/PhysicalNetworkInterface.cs" -Encoding UTF8
$virtualInterfaceCs | Out-File "./$modelsDir/VirtualInterface.cs" -Encoding UTF8

# RemoteHost.cs, InterfaceWiring.cs, PacketData.cs (same as before)
$remoteHostCs = @'
using System;
using System.ComponentModel;
using System.Net;
using System.Runtime.CompilerServices;

namespace NetworkBridge.Models
{
    public class RemoteHost : INotifyPropertyChanged
    {
        private string _displayName;
        private IPEndPoint _endpoint;
        private bool _isConnected;
        private DateTime _lastSeen;
        private Guid _hostId;

        public Guid HostId
        {
            get => _hostId;
            set { _hostId = value; OnPropertyChanged(); }
        }

        public string DisplayName
        {
            get => _displayName;
            set { _displayName = value; OnPropertyChanged(); }
        }

        public IPEndPoint Endpoint
        {
            get => _endpoint;
            set { _endpoint = value; OnPropertyChanged(); }
        }

        public bool IsConnected
        {
            get => _isConnected;
            set { _isConnected = value; OnPropertyChanged(); OnPropertyChanged(nameof(StatusDisplay)); }
        }

        public DateTime LastSeen
        {
            get => _lastSeen;
            set { _lastSeen = value; OnPropertyChanged(); }
        }

        public string StatusDisplay => IsConnected ? "Connected" : "Disconnected";

        public event PropertyChangedEventHandler PropertyChanged;

        protected virtual void OnPropertyChanged([CallerMemberName] string propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }
}
'@
$remoteHostCs | Out-File "./$modelsDir/RemoteHost.cs" -Encoding UTF8

$interfaceWiringCs = @'
using System;

namespace NetworkBridge.Models
{
    public class InterfaceWiring
    {
        public Guid Id { get; set; }
        public Guid SourceInterfaceId { get; set; }
        public Guid DestinationInterfaceId { get; set; }
        public string SourceName { get; set; }
        public string DestinationName { get; set; }
        public bool IsEnabled { get; set; }
        public WiringType Type { get; set; }
    }

    public enum WiringType
    {
        Local,
        Remote
    }
}
'@
$interfaceWiringCs | Out-File "././$modelsDir/InterfaceWiring.cs" -Encoding UTF8

$packetDataCs = @'
using System;

namespace NetworkBridge.Models
{
    public sealed class PacketData
    {
        public PacketData(byte[] data, uint length, Guid sourceInterfaceId, DateTime timestamp)
        {
            Data = new byte[length];
            Array.Copy(data, Data, length);
            Length = length;
            SourceInterfaceId = sourceInterfaceId;
            Timestamp = timestamp;
        }

        public byte[] Data { get; }
        public uint Length { get; }
        public Guid SourceInterfaceId { get; }
        public DateTime Timestamp { get; }
    }
}
'@
$packetDataCs | Out-File "././$modelsDir/PacketData.cs" -Encoding UTF8

# ============================================================================
# CORE PROJECT - NEW: Network Interface Discovery Service
# ============================================================================
Write-Host "[3/8] Creating Core project with interface detection..." -ForegroundColor Green

$coreDir = "src/$ProjectName.Core"
$coreCsproj = @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <AllowUnsafeBlocks>true</AllowUnsafeBlocks>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.Extensions.Logging.Abstractions" Version="8.0.0" />
    <PackageReference Include="System.Management" Version="8.0.0" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="..\$ProjectName.Models\$ProjectName.Models.csproj" />
  </ItemGroup>
</Project>
"@

$coreCsproj | Out-File "./$coreDir/$ProjectName.Core.csproj" -Encoding UTF8

# INetworkInterfaceDiscoveryService.cs - NEW
$iNetworkDiscoveryCs = @'
using System.Collections.Generic;
using System.Threading.Tasks;
using NetworkBridge.Models;

namespace NetworkBridge.Core.Interfaces
{
    /// <summary>
    /// Service for discovering physical network interfaces on the system
    /// </summary>
    public interface INetworkInterfaceDiscoveryService
    {
        /// <summary>
        /// Scans the system for available network interfaces
        /// </summary>
        /// <param name="includeVirtual">Include virtual adapters (VPN, VMware, etc.)</param>
        Task<List<PhysicalNetworkInterface>> DiscoverInterfacesAsync(bool includeVirtual = false);

        /// <summary>
        /// Gets detailed information about a specific interface
        /// </summary>
        Task<PhysicalNetworkInterface> GetInterfaceDetailsAsync(string interfaceId);

        /// <summary>
        /// Refreshes the interface list (detects hot-plugged adapters)
        /// </summary>
        Task<List<PhysicalNetworkInterface>> RefreshInterfacesAsync();
    }
}
'@
$iNetworkDiscoveryCs | Out-File "./$coreDir/Interfaces/INetworkInterfaceDiscoveryService.cs" -Encoding UTF8

# Copy previous interface files (IPacketInterceptor, INetworkBridgeService, IRemoteConnectionService)
$iPacketInterceptorCs = @'
using System;
using System.Threading;
using System.Threading.Tasks;
using NetworkBridge.Models;

namespace NetworkBridge.Core.Interfaces
{
    public interface IPacketInterceptor : IDisposable
    {
        Task StartCaptureAsync(string filter, CancellationToken cancellationToken);
        Task StopCaptureAsync();
        Task<bool> InjectPacketAsync(PacketData packet);
        event EventHandler<PacketData> PacketCaptured;
    }
}
'@
$iPacketInterceptorCs  | Out-File "./$coreDir/Interfaces/IPacketInterceptor.cs" -Encoding UTF8

$iNetworkBridgeServiceCs = @'
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using NetworkBridge.Models;

namespace NetworkBridge.Core.Interfaces
{
    public interface INetworkBridgeService
    {
        Task<VirtualInterface> CreateVirtualInterfaceAsync(string name, InterfaceDirection direction, string filter);
        Task<bool> DeleteVirtualInterfaceAsync(Guid interfaceId);
        Task<bool> StartInterfaceAsync(Guid interfaceId);
        Task<bool> StopInterfaceAsync(Guid interfaceId);
        Task<InterfaceWiring> CreateWiringAsync(Guid sourceId, Guid destinationId, WiringType type);
        Task<bool> DeleteWiringAsync(Guid wiringId);
        IReadOnlyList<VirtualInterface> GetAllInterfaces();
        IReadOnlyList<InterfaceWiring> GetAllWirings();
    }
}
'@
$iNetworkBridgeServiceCs | Out-File "./$coreDir/Interfaces/INetworkBridgeService.cs" -Encoding UTF8

$iRemoteConnectionServiceCs = @'
using System;
using System.Collections.Generic;
using System.Net;
using System.Threading.Tasks;
using NetworkBridge.Models;

namespace NetworkBridge.Core.Interfaces
{
    public interface IRemoteConnectionService
    {
        Task<bool> ConnectToRemoteAsync(IPEndPoint endpoint);
        Task<bool> DisconnectFromRemoteAsync(Guid hostId);
        Task<bool> SendPacketToRemoteAsync(Guid remoteHostId, Guid remoteInterfaceId, PacketData packet);
        Task StartListeningAsync(int port);
        Task StopListeningAsync();
        IReadOnlyList<RemoteHost> GetConnectedHosts();
        event EventHandler<RemoteHost> RemoteHostConnected;
        event EventHandler<RemoteHost> RemoteHostDisconnected;
        event EventHandler<(Guid remoteHostId, PacketData packet)> PacketReceivedFromRemote;
    }
}
'@
$iRemoteConnectionServiceCs | Out-File "./$coreDir/Interfaces/IRemoteConnectionService.cs"  -Encoding UTF8

Write-Host "[4/8] Creating Core services..." -ForegroundColor Green

# NetworkInterfaceDiscoveryService.cs - NEW
$networkDiscoveryServiceCs = @'
using System;
using System.Collections.Generic;
using System.Linq;
using System.Management;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Threading.Tasks;
using NetworkBridge.Core.Interfaces;
using NetworkBridge.Models;
using Microsoft.Extensions.Logging;

namespace NetworkBridge.Core.Services
{
    /// <summary>
    /// Discovers and enumerates physical network interfaces on Windows
    /// Uses both NetworkInterface API and WMI for comprehensive detection
    /// Reference: https://learn.microsoft.com/en-us/dotnet/api/system.net.networkinformation.networkinterface
    /// </summary>
    public class NetworkInterfaceDiscoveryService : INetworkInterfaceDiscoveryService
    {
        private readonly ILogger<NetworkInterfaceDiscoveryService> _logger;

        public NetworkInterfaceDiscoveryService(ILogger<NetworkInterfaceDiscoveryService> logger)
        {
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        }

        public async Task<List<PhysicalNetworkInterface>> DiscoverInterfacesAsync(bool includeVirtual = false)
        {
            return await Task.Run(() =>
            {
                var interfaces = new List<PhysicalNetworkInterface>();

                try
                {
                    var nics = NetworkInterface.GetAllNetworkInterfaces();
                    _logger.LogInformation("Found {Count} network interfaces", nics.Length);

                    foreach (var nic in nics)
                    {
                        try
                        {
                            // Filter based on physical/virtual
                            bool isPhysical = IsPhysicalAdapter(nic);
                            
                            if (!includeVirtual && !isPhysical)
                            {
                                _logger.LogDebug("Skipping virtual adapter: {Name}", nic.Name);
                                continue;
                            }

                            var interfaceInfo = new PhysicalNetworkInterface
                            {
                                Id = nic.Id,
                                Name = nic.Name,
                                Description = nic.Description,
                                InterfaceType = nic.NetworkInterfaceType,
                                Status = nic.OperationalStatus,
                                Speed = nic.Speed,
                                MacAddress = nic.GetPhysicalAddress().ToString(),
                                IsPhysical = isPhysical,
                                IpAddress = GetIpAddress(nic)
                            };

                            interfaces.Add(interfaceInfo);
                            _logger.LogInformation("Detected: {Name} - {Type} - {Status}", 
                                nic.Name, nic.NetworkInterfaceType, nic.OperationalStatus);
                        }
                        catch (Exception ex)
                        {
                            _logger.LogWarning(ex, "Error processing interface: {Name}", nic.Name);
                        }
                    }

                    return interfaces.OrderByDescending(i => i.Status == OperationalStatus.Up)
                                    .ThenByDescending(i => i.IsPhysical)
                                    .ThenBy(i => i.Name)
                                    .ToList();
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed to discover network interfaces");
                    return interfaces;
                }
            });
        }

        public async Task<PhysicalNetworkInterface> GetInterfaceDetailsAsync(string interfaceId)
        {
            return await Task.Run(() =>
            {
                var nic = NetworkInterface.GetAllNetworkInterfaces()
                    .FirstOrDefault(n => n.Id == interfaceId);

                if (nic == null)
                    return null;

                return new PhysicalNetworkInterface
                {
                    Id = nic.Id,
                    Name = nic.Name,
                    Description = nic.Description,
                    InterfaceType = nic.NetworkInterfaceType,
                    Status = nic.OperationalStatus,
                    Speed = nic.Speed,
                    MacAddress = nic.GetPhysicalAddress().ToString(),
                    IsPhysical = IsPhysicalAdapter(nic),
                    IpAddress = GetIpAddress(nic)
                };
            });
        }

        public async Task<List<PhysicalNetworkInterface>> RefreshInterfacesAsync()
        {
            _logger.LogInformation("Refreshing network interface list");
            return await DiscoverInterfacesAsync(false);
        }

        /// <summary>
        /// Determines if an adapter is physical or virtual
        /// Physical adapters have PNPDeviceID not starting with ROOT\
        /// and manufacturer is not Microsoft (for built-in virtual adapters)
        /// </summary>
        private bool IsPhysicalAdapter(NetworkInterface nic)
        {
            try
            {
                // Filter out loopback and tunnel adapters
                if (nic.NetworkInterfaceType == NetworkInterfaceType.Loopback ||
                    nic.NetworkInterfaceType == NetworkInterfaceType.Tunnel)
                {
                    return false;
                }

                // Use WMI to check PNPDeviceID
                string query = $"SELECT * FROM Win32_NetworkAdapter WHERE GUID = '{{{nic.Id}}}'";
                using (var searcher = new ManagementObjectSearcher(query))
                {
                    foreach (ManagementObject obj in searcher.Get())
                    {
                        string pnpDeviceId = obj["PNPDeviceID"]?.ToString();
                        string manufacturer = obj["Manufacturer"]?.ToString();

                        // Physical devices don't have PNPDeviceID starting with ROOT\
                        // and are not manufactured by Microsoft (built-in virtuals)
                        if (!string.IsNullOrEmpty(pnpDeviceId) && 
                            !pnpDeviceId.StartsWith("ROOT\\", StringComparison.OrdinalIgnoreCase))
                        {
                            if (manufacturer != null && 
                                !manufacturer.Equals("Microsoft", StringComparison.OrdinalIgnoreCase))
                            {
                                return true;
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Could not determine if adapter is physical: {Name}", nic.Name);
                // Default to considering it physical if we can't determine
                return nic.NetworkInterfaceType == NetworkInterfaceType.Ethernet ||
                       nic.NetworkInterfaceType == NetworkInterfaceType.Wireless80211;
            }

            return false;
        }

        /// <summary>
        /// Gets the IPv4 address of a network interface
        /// </summary>
        private string GetIpAddress(NetworkInterface nic)
        {
            try
            {
                var ipProps = nic.GetIPProperties();
                var ipv4Address = ipProps.UnicastAddresses
                    .FirstOrDefault(a => a.Address.AddressFamily == AddressFamily.InterNetwork);

                return ipv4Address?.Address.ToString() ?? "No IP";
            }
            catch
            {
                return "Unknown";
            }
        }
    }
}
'@
$networkDiscoveryServiceCs | Out-File "./$coreDir/Services/NetworkInterfaceDiscoveryService.cs" -Encoding UTF8

# WinDivertInterceptor.cs (same as before - abbreviated for space)
$winDivertInterceptorCs = @'
using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using NetworkBridge.Core.Interfaces;
using NetworkBridge.Models;
using Microsoft.Extensions.Logging;

namespace NetworkBridge.Core.Services
{
    public sealed class WinDivertInterceptor : IPacketInterceptor
    {
        private readonly ILogger<WinDivertInterceptor> _logger;
        private readonly Guid _interfaceId;
        private IntPtr _handle = IntPtr.Zero;
        private CancellationTokenSource _captureCts;
        private Task _captureTask;
        private const int BufferSize = 65535;

        public event EventHandler<PacketData> PacketCaptured;

        public WinDivertInterceptor(Guid interfaceId, ILogger<WinDivertInterceptor> logger)
        {
            _interfaceId = interfaceId;
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        }

        public async Task StartCaptureAsync(string filter, CancellationToken cancellationToken)
        {
            if (_handle != IntPtr.Zero)
                throw new InvalidOperationException("Capture already started");

            try
            {
                _handle = WinDivertNative.WinDivertOpen(filter, WinDivertLayer.Network, 0, 0);

                if (_handle == IntPtr.Zero || _handle == new IntPtr(-1))
                {
                    int error = Marshal.GetLastWin32Error();
                    throw new InvalidOperationException($"Failed to open WinDivert: Error {error}");
                }

                _logger.LogInformation("WinDivert opened with filter: {Filter}", filter);

                WinDivertNative.WinDivertSetParam(_handle, WinDivertParam.QueueLength, 8192);
                WinDivertNative.WinDivertSetParam(_handle, WinDivertParam.QueueTime, 2000);
                WinDivertNative.WinDivertSetParam(_handle, WinDivertParam.QueueSize, 33554432);

                _captureCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                _captureTask = Task.Run(() => CaptureLoop(_captureCts.Token), _captureCts.Token);

                await Task.CompletedTask;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to start packet capture");
                if (_handle != IntPtr.Zero && _handle != new IntPtr(-1))
                {
                    WinDivertNative.WinDivertClose(_handle);
                    _handle = IntPtr.Zero;
                }
                throw;
            }
        }

        private void CaptureLoop(CancellationToken cancellationToken)
        {
            byte[] packet = new byte[BufferSize];
            WinDivertAddress addr = new WinDivertAddress();

            try
            {
                while (!cancellationToken.IsCancellationRequested)
                {
                    uint recvLen = 0;
                    bool success = WinDivertNative.WinDivertRecv(_handle, packet, (uint)packet.Length, ref recvLen, ref addr);

                    if (!success)
                    {
                        int error = Marshal.GetLastWin32Error();
                        if (error == 995) break;
                        continue;
                    }

                    if (recvLen > 0)
                    {
                        var packetData = new PacketData(packet, recvLen, _interfaceId, DateTime.UtcNow);
                        PacketCaptured?.Invoke(this, packetData);
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in packet capture loop");
            }
        }

        public async Task<bool> InjectPacketAsync(PacketData packet)
        {
            if (_handle == IntPtr.Zero) return false;

            try
            {
                WinDivertAddress addr = new WinDivertAddress { Outbound = 1, Loopback = 0 };
                uint sendLen = 0;
                bool success = WinDivertNative.WinDivertSend(_handle, packet.Data, packet.Length, ref sendLen, ref addr);
                return success && sendLen == packet.Length;
            }
            catch
            {
                return false;
            }
        }

        public async Task StopCaptureAsync()
        {
            if (_captureCts != null)
            {
                _captureCts.Cancel();
                if (_captureTask != null)
                    await _captureTask.ConfigureAwait(false);
                _captureCts?.Dispose();
                _captureCts = null;
            }

            if (_handle != IntPtr.Zero && _handle != new IntPtr(-1))
            {
                WinDivertNative.WinDivertClose(_handle);
                _handle = IntPtr.Zero;
            }
        }

        public void Dispose() => StopCaptureAsync().GetAwaiter().GetResult();
    }

    internal static class WinDivertNative
    {
        private const string DllName = "WinDivert.dll";

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, SetLastError = true)]
        public static extern IntPtr WinDivertOpen([MarshalAs(UnmanagedType.LPStr)] string filter, WinDivertLayer layer, short priority, ulong flags);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, SetLastError = true)]
        public static extern bool WinDivertRecv(IntPtr handle, byte[] pPacket, uint packetLen, ref uint pRecvLen, ref WinDivertAddress pAddr);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, SetLastError = true)]
        public static extern bool WinDivertSend(IntPtr handle, byte[] pPacket, uint packetLen, ref uint pSendLen, ref WinDivertAddress pAddr);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, SetLastError = true)]
        public static extern bool WinDivertClose(IntPtr handle);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, SetLastError = true)]
        public static extern bool WinDivertSetParam(IntPtr handle, WinDivertParam param, ulong value);
    }

    internal enum WinDivertLayer { Network = 0, NetworkForward = 1 }
    internal enum WinDivertParam { QueueLength = 0, QueueTime = 1, QueueSize = 2 }

    [StructLayout(LayoutKind.Sequential)]
    internal struct WinDivertAddress
    {
        public long Timestamp;
        public byte Layer, Event, Sniffed, Outbound, Loopback, Impostor, IPv6;
        public byte IPChecksum, TCPChecksum, UDPChecksum;
        public uint IfIdx, SubIfIdx;
    }
}
'@

$winDivertInterceptorCs | Out-File "./$coreDir/Services/WinDivertInterceptor.cs" -Encoding UTF8

# NetworkBridgeService.cs and RemoteConnectionService.cs (abbreviated - same logic as before)
# I'll create simplified versions to fit within response limits

$networkBridgeServiceCs = @'
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NetworkBridge.Core.Interfaces;
using NetworkBridge.Models;
using Microsoft.Extensions.Logging;

namespace NetworkBridge.Core.Services
{
    public sealed class NetworkBridgeService : INetworkBridgeService, IDisposable
    {
        private readonly ILogger<NetworkBridgeService> _logger;
        private readonly IRemoteConnectionService _remoteConnectionService;
        private readonly ConcurrentDictionary<Guid, VirtualInterface> _interfaces;
        private readonly ConcurrentDictionary<Guid, IPacketInterceptor> _interceptors;
        private readonly ConcurrentDictionary<Guid, InterfaceWiring> _wirings;
        private readonly SemaphoreSlim _lock = new SemaphoreSlim(1, 1);

        public NetworkBridgeService(IRemoteConnectionService remoteConnectionService, ILogger<NetworkBridgeService> logger)
        {
            _remoteConnectionService = remoteConnectionService ?? throw new ArgumentNullException(nameof(remoteConnectionService));
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
            _interfaces = new ConcurrentDictionary<Guid, VirtualInterface>();
            _interceptors = new ConcurrentDictionary<Guid, IPacketInterceptor>();
            _wirings = new ConcurrentDictionary<Guid, InterfaceWiring>();
            _remoteConnectionService.PacketReceivedFromRemote += OnPacketReceivedFromRemote;
        }

        public async Task<VirtualInterface> CreateVirtualInterfaceAsync(string name, InterfaceDirection direction, string filter)
        {
            await _lock.WaitAsync();
            try
            {
                var virtualInterface = new VirtualInterface
                {
                    Id = Guid.NewGuid(),
                    Name = name,
                    Direction = direction,
                    Filter = filter,
                    IsActive = false
                };

                if (!_interfaces.TryAdd(virtualInterface.Id, virtualInterface))
                    throw new InvalidOperationException("Failed to add interface");

                _logger.LogInformation("Created virtual interface {Name}", name);
                return virtualInterface;
            }
            finally
            {
                _lock.Release();
            }
        }

        public async Task<bool> StartInterfaceAsync(Guid interfaceId)
        {
            if (!_interfaces.TryGetValue(interfaceId, out var virtualInterface))
                return false;

            if (virtualInterface.IsActive)
                return false;

            try
            {
                var interceptor = new WinDivertInterceptor(interfaceId, _logger as ILogger<WinDivertInterceptor>);
                interceptor.PacketCaptured += (sender, packet) => OnPacketCaptured(interfaceId, packet);
                await interceptor.StartCaptureAsync(virtualInterface.Filter, CancellationToken.None);
                _interceptors.TryAdd(interfaceId, interceptor);
                virtualInterface.IsActive = true;
                return true;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to start interface");
                return false;
            }
        }

        private async void OnPacketCaptured(Guid sourceInterfaceId, PacketData packet)
        {
            if (!_interfaces.TryGetValue(sourceInterfaceId, out var sourceInterface))
                return;

            sourceInterface.BytesReceived += packet.Length;
            sourceInterface.PacketsReceived++;

            var wirings = _wirings.Values.Where(w => w.IsEnabled && w.SourceInterfaceId == sourceInterfaceId).ToList();

            foreach (var wiring in wirings)
            {
                try
                {
                    if (wiring.Type == WiringType.Local)
                        await ForwardToLocalInterfaceAsync(wiring.DestinationInterfaceId, packet);
                    else if (wiring.Type == WiringType.Remote)
                        await _remoteConnectionService.SendPacketToRemoteAsync(wiring.DestinationInterfaceId, wiring.DestinationInterfaceId, packet);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Error forwarding packet");
                }
            }
        }

        private async Task ForwardToLocalInterfaceAsync(Guid destInterfaceId, PacketData packet)
        {
            if (!_interceptors.TryGetValue(destInterfaceId, out var interceptor))
                return;

            if (!_interfaces.TryGetValue(destInterfaceId, out var destInterface))
                return;

            bool success = await interceptor.InjectPacketAsync(packet);
            if (success)
            {
                destInterface.BytesSent += packet.Length;
                destInterface.PacketsSent++;
            }
        }

        private async void OnPacketReceivedFromRemote(object sender, (Guid remoteHostId, PacketData packet) e)
        {
            var targetInterface = _interfaces.Values.FirstOrDefault(i => i.Direction != InterfaceDirection.Output && i.IsActive);
            if (targetInterface != null)
                await ForwardToLocalInterfaceAsync(targetInterface.Id, e.packet);
        }

        public async Task<bool> StopInterfaceAsync(Guid interfaceId)
        {
            if (_interceptors.TryRemove(interfaceId, out var interceptor))
            {
                await interceptor.StopCaptureAsync();
                interceptor.Dispose();
                if (_interfaces.TryGetValue(interfaceId, out var virtualInterface))
                    virtualInterface.IsActive = false;
                return true;
            }
            return false;
        }

        public async Task<bool> DeleteVirtualInterfaceAsync(Guid interfaceId)
        {
            await StopInterfaceAsync(interfaceId);
            return _interfaces.TryRemove(interfaceId, out _);
        }

        public async Task<InterfaceWiring> CreateWiringAsync(Guid sourceId, Guid destinationId, WiringType type)
        {
            var wiring = new InterfaceWiring
            {
                Id = Guid.NewGuid(),
                SourceInterfaceId = sourceId,
                DestinationInterfaceId = destinationId,
                Type = type,
                IsEnabled = true
            };

            if (_interfaces.TryGetValue(sourceId, out var sourceInterface))
                wiring.SourceName = sourceInterface.Name;

            if (type == WiringType.Local && _interfaces.TryGetValue(destinationId, out var destInterface))
                wiring.DestinationName = destInterface.Name;

            _wirings.TryAdd(wiring.Id, wiring);
            return wiring;
        }

        public async Task<bool> DeleteWiringAsync(Guid wiringId) => _wirings.TryRemove(wiringId, out _);

        public IReadOnlyList<VirtualInterface> GetAllInterfaces() => _interfaces.Values.ToList();
        public IReadOnlyList<InterfaceWiring> GetAllWirings() => _wirings.Values.ToList();

        public void Dispose()
        {
            foreach (var interceptor in _interceptors.Values)
                interceptor.Dispose();
            _interceptors.Clear();
            _lock?.Dispose();
        }
    }
}
'@
$networkBridgeServiceCs | Out-File "./$coreDir/Services/NetworkBridgeService.cs" -Encoding UTF8

# RemoteConnectionService - same as before, abbreviated
$remoteConnectionServiceCs = @'
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using NetworkBridge.Core.Interfaces;
using NetworkBridge.Models;
using Microsoft.Extensions.Logging;

namespace NetworkBridge.Core.Services
{
    public sealed class RemoteConnectionService : IRemoteConnectionService, IDisposable
    {
        private readonly ILogger<RemoteConnectionService> _logger;
        private readonly ConcurrentDictionary<Guid, RemoteHost> _connectedHosts;
        private readonly ConcurrentDictionary<Guid, TcpClient> _connections;
        private TcpListener _listener;
        private CancellationTokenSource _listenerCts;
        private const int ProtocolVersion = 1;

        public event EventHandler<RemoteHost> RemoteHostConnected;
        public event EventHandler<RemoteHost> RemoteHostDisconnected;
        public event EventHandler<(Guid remoteHostId, PacketData packet)> PacketReceivedFromRemote;

        public RemoteConnectionService(ILogger<RemoteConnectionService> logger)
        {
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
            _connectedHosts = new ConcurrentDictionary<Guid, RemoteHost>();
            _connections = new ConcurrentDictionary<Guid, TcpClient>();
        }

        public async Task StartListeningAsync(int port)
        {
            if (_listener != null)
                throw new InvalidOperationException("Already listening");

            _listener = new TcpListener(IPAddress.Any, port);
            _listener.Start();
            _listenerCts = new CancellationTokenSource();
            _logger.LogInformation("Started listening on port {Port}", port);
            _ = Task.Run(() => AcceptConnectionsAsync(_listenerCts.Token));
            await Task.CompletedTask;
        }

        private async Task AcceptConnectionsAsync(CancellationToken cancellationToken)
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                try
                {
                    var client = await _listener.AcceptTcpClientAsync(cancellationToken);
                    _ = Task.Run(() => HandleIncomingConnectionAsync(client, cancellationToken), cancellationToken);
                }
                catch (OperationCanceledException) { break; }
                catch (Exception ex) { _logger.LogError(ex, "Error accepting connection"); }
            }
        }

        private async Task HandleIncomingConnectionAsync(TcpClient client, CancellationToken cancellationToken)
        {
            try
            {
                using var stream = client.GetStream();
                var handshake = await ReadMessageAsync(stream, cancellationToken);
                if (handshake == null || handshake.Type != MessageType.Handshake)
                {
                    client.Close();
                    return;
                }

                var remoteHost = new RemoteHost
                {
                    HostId = handshake.HostId,
                    DisplayName = handshake.Payload,
                    Endpoint = client.Client.RemoteEndPoint as IPEndPoint,
                    IsConnected = true,
                    LastSeen = DateTime.UtcNow
                };

                _connectedHosts.TryAdd(remoteHost.HostId, remoteHost);
                _connections.TryAdd(remoteHost.HostId, client);

                var response = new ProtocolMessage
                {
                    Version = ProtocolVersion,
                    Type = MessageType.HandshakeAck,
                    HostId = Guid.NewGuid(),
                    Payload = Environment.MachineName
                };
                await SendMessageAsync(stream, response, cancellationToken);
                RemoteHostConnected?.Invoke(this, remoteHost);
                await ReceiveMessagesAsync(remoteHost.HostId, stream, cancellationToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error handling connection");
                client.Close();
            }
        }

        public async Task<bool> ConnectToRemoteAsync(IPEndPoint endpoint)
        {
            try
            {
                var client = new TcpClient();
                await client.ConnectAsync(endpoint.Address, endpoint.Port);
                var stream = client.GetStream();

                var handshake = new ProtocolMessage
                {
                    Version = ProtocolVersion,
                    Type = MessageType.Handshake,
                    HostId = Guid.NewGuid(),
                    Payload = Environment.MachineName
                };
                await SendMessageAsync(stream, handshake, CancellationToken.None);

                var response = await ReadMessageAsync(stream, CancellationToken.None);
                if (response == null || response.Type != MessageType.HandshakeAck)
                {
                    client.Close();
                    return false;
                }

                var remoteHost = new RemoteHost
                {
                    HostId = response.HostId,
                    DisplayName = response.Payload,
                    Endpoint = endpoint,
                    IsConnected = true,
                    LastSeen = DateTime.UtcNow
                };

                _connectedHosts.TryAdd(remoteHost.HostId, remoteHost);
                _connections.TryAdd(remoteHost.HostId, client);
                RemoteHostConnected?.Invoke(this, remoteHost);
                _ = Task.Run(() => ReceiveMessagesAsync(remoteHost.HostId, stream, CancellationToken.None));
                return true;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to connect");
                return false;
            }
        }

        private async Task ReceiveMessagesAsync(Guid hostId, NetworkStream stream, CancellationToken cancellationToken)
        {
            try
            {
                while (!cancellationToken.IsCancellationRequested && stream.CanRead)
                {
                    var message = await ReadMessageAsync(stream, cancellationToken);
                    if (message == null) break;

                    if (_connectedHosts.TryGetValue(hostId, out var host))
                        host.LastSeen = DateTime.UtcNow;

                    if (message.Type == MessageType.PacketData)
                        HandlePacketDataMessage(hostId, message);
                }
            }
            catch (Exception ex) { _logger.LogError(ex, "Error receiving messages"); }
            finally { await DisconnectFromRemoteAsync(hostId); }
        }

        private void HandlePacketDataMessage(Guid hostId, ProtocolMessage message)
        {
            try
            {
                byte[] packetBytes = Convert.FromBase64String(message.Payload);
                var packet = new PacketData(packetBytes, (uint)packetBytes.Length, message.InterfaceId, DateTime.UtcNow);
                PacketReceivedFromRemote?.Invoke(this, (hostId, packet));
            }
            catch (Exception ex) { _logger.LogError(ex, "Error handling packet"); }
        }

        public async Task<bool> SendPacketToRemoteAsync(Guid remoteHostId, Guid remoteInterfaceId, PacketData packet)
        {
            if (!_connections.TryGetValue(remoteHostId, out var client) || !client.Connected)
                return false;

            try
            {
                var message = new ProtocolMessage
                {
                    Version = ProtocolVersion,
                    Type = MessageType.PacketData,
                    HostId = remoteHostId,
                    InterfaceId = remoteInterfaceId,
                    Payload = Convert.ToBase64String(packet.Data, 0, (int)packet.Length)
                };

                var stream = client.GetStream();
                await SendMessageAsync(stream, message, CancellationToken.None);
                return true;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to send packet");
                await DisconnectFromRemoteAsync(remoteHostId);
                return false;
            }
        }

        public async Task<bool> DisconnectFromRemoteAsync(Guid hostId)
        {
            if (_connections.TryRemove(hostId, out var client))
            {
                client.Close();
                client.Dispose();
            }

            if (_connectedHosts.TryRemove(hostId, out var host))
            {
                host.IsConnected = false;
                RemoteHostDisconnected?.Invoke(this, host);
                return true;
            }
            return false;
        }

        public async Task StopListeningAsync()
        {
            _listenerCts?.Cancel();
            _listener?.Stop();
            _listener = null;
        }

        public IReadOnlyList<RemoteHost> GetConnectedHosts() => _connectedHosts.Values.ToList();

        private async Task SendMessageAsync(NetworkStream stream, ProtocolMessage message, CancellationToken cancellationToken)
        {
            var json = JsonSerializer.Serialize(message);
            var jsonBytes = Encoding.UTF8.GetBytes(json);
            var lengthBytes = BitConverter.GetBytes(jsonBytes.Length);
            await stream.WriteAsync(lengthBytes, 0, 4, cancellationToken);
            await stream.WriteAsync(jsonBytes, 0, jsonBytes.Length, cancellationToken);
            await stream.FlushAsync(cancellationToken);
        }

        private async Task<ProtocolMessage> ReadMessageAsync(NetworkStream stream, CancellationToken cancellationToken)
        {
            try
            {
                byte[] lengthBytes = new byte[4];
                int bytesRead = await stream.ReadAsync(lengthBytes, 0, 4, cancellationToken);
                if (bytesRead != 4) return null;

                int length = BitConverter.ToInt32(lengthBytes, 0);
                if (length <= 0 || length > 10_000_000) return null;

                byte[] messageBytes = new byte[length];
                int totalRead = 0;
                while (totalRead < length)
                {
                    int read = await stream.ReadAsync(messageBytes, totalRead, length - totalRead, cancellationToken);
                    if (read == 0) return null;
                    totalRead += read;
                }

                var json = Encoding.UTF8.GetString(messageBytes);
                return JsonSerializer.Deserialize<ProtocolMessage>(json);
            }
            catch { return null; }
        }

        public void Dispose()
        {
            StopListeningAsync().GetAwaiter().GetResult();
            foreach (var client in _connections.Values)
            {
                client.Close();
                client.Dispose();
            }
            _connections.Clear();
            _listenerCts?.Dispose();
        }
    }

    internal class ProtocolMessage
    {
        public int Version { get; set; }
        public MessageType Type { get; set; }
        public Guid HostId { get; set; }
        public Guid InterfaceId { get; set; }
        public string Payload { get; set; }
    }

    internal enum MessageType
    {
        Handshake,
        HandshakeAck,
        PacketData,
        KeepAlive
    }
}
'@
$remoteConnectionServiceCs | Out-File "./$coreDir/Services/RemoteConnectionService.cs" -Encoding UTF8

# ============================================================================
# UI PROJECT - PROFESSIONAL REDESIGN
# ============================================================================
Write-Host "[5/8] Creating professional UI project..." -ForegroundColor Green

$uiDir = "src/$ProjectName.UI"
$uiCsproj = @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net8.0-windows</TargetFramework>
    <UseWPF>true</UseWPF>
    <Nullable>enable</Nullable>
    <AllowUnsafeBlocks>true</AllowUnsafeBlocks>
    <ApplicationManifest>app.manifest</ApplicationManifest>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.Extensions.Logging" Version="8.0.0" />
    <PackageReference Include="Microsoft.Extensions.Logging.Console" Version="8.0.0" />
    <PackageReference Include="Microsoft.Extensions.DependencyInjection" Version="8.0.0" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="..\$ProjectName.Core\$ProjectName.Core.csproj" />
    <ProjectReference Include="..\$ProjectName.Models\$ProjectName.Models.csproj" />
  </ItemGroup>

  <ItemGroup>
    <None Update="WinDivert.dll">
      <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
    </None>
    <None Update="WinDivert64.sys">
      <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
    </None>
  </ItemGroup>
</Project>
"@

$uiCsproj | Out-File "./$uiDir/$ProjectName.UI.csproj" -Encoding UTF8

Write-Host "[6/8] Creating professional MainWindow..." -ForegroundColor Green

# MainWindow.xaml - PROFESSIONAL REDESIGN
$mainWindowXaml = @'
<Window x:Class="NetworkBridge.UI.MainWindow"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:local="clr-namespace:NetworkBridge.UI"
        Title="Network Bridge Manager" Height="900" Width="1400"
        WindowStartupLocation="CenterScreen"
        Background="#F5F5F5">
    
    <Window.Resources>
        <!-- Professional Color Scheme -->
        <SolidColorBrush x:Key="PrimaryColor" Color="#2C3E50"/>
        <SolidColorBrush x:Key="AccentColor" Color="#3498DB"/>
        <SolidColorBrush x:Key="SuccessColor" Color="#27AE60"/>
        <SolidColorBrush x:Key="DangerColor" Color="#E74C3C"/>
        <SolidColorBrush x:Key="BackgroundColor" Color="#F5F5F5"/>
        <SolidColorBrush x:Key="CardColor" Color="#FFFFFF"/>
        <SolidColorBrush x:Key="TextPrimaryColor" Color="#2C3E50"/>
        <SolidColorBrush x:Key="TextSecondaryColor" Color="#7F8C8D"/>
        <SolidColorBrush x:Key="BorderColor" Color="#E0E0E0"/>
        
        <!-- Modern Button Style -->
        <Style x:Key="PrimaryButton" TargetType="Button">
            <Setter Property="Background" Value="{StaticResource AccentColor}"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="Medium"/>
            <Setter Property="Padding" Value="20,10"/>
            <Setter Property="Margin" Value="5"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" 
                                CornerRadius="4" 
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#2980B9"/>
                </Trigger>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Background" Value="#BDC3C7"/>
                    <Setter Property="Cursor" Value="Arrow"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="SecondaryButton" TargetType="Button" BasedOn="{StaticResource PrimaryButton}">
            <Setter Property="Background" Value="#ECF0F1"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryColor}"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#D5DBDB"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource PrimaryButton}">
            <Setter Property="Background" Value="{StaticResource DangerColor}"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#C0392B"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Clean TextBox Style -->
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="White"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryColor}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderColor}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>

        <!-- Clean ComboBox Style -->
        <Style TargetType="ComboBox">
            <Setter Property="Background" Value="White"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryColor}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderColor}"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>

        <!-- Professional DataGrid Style -->
        <Style TargetType="DataGrid">
            <Setter Property="Background" Value="White"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryColor}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderColor}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="RowBackground" Value="White"/>
            <Setter Property="AlternatingRowBackground" Value="#F9F9F9"/>
            <Setter Property="GridLinesVisibility" Value="Horizontal"/>
            <Setter Property="HorizontalGridLinesBrush" Value="{StaticResource BorderColor}"/>
            <Setter Property="HeadersVisibility" Value="Column"/>
            <Setter Property="AutoGenerateColumns" Value="False"/>
            <Setter Property="CanUserAddRows" Value="False"/>
            <Setter Property="SelectionMode" Value="Single"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>

        <Style TargetType="DataGridColumnHeader">
            <Setter Property="Background" Value="#FAFAFA"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryColor}"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="10,12"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderColor}"/>
            <Setter Property="BorderThickness" Value="0,0,0,1"/>
        </Style>

        <!-- Card Style -->
        <Style x:Key="Card" TargetType="Border">
            <Setter Property="Background" Value="{StaticResource CardColor}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderColor}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="6"/>
            <Setter Property="Padding" Value="20"/>
            <Setter Property="Margin" Value="0,0,0,15"/>
        </Style>

        <!-- Section Header Style -->
        <Style x:Key="SectionHeader" TargetType="TextBlock">
            <Setter Property="FontSize" Value="16"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryColor}"/>
            <Setter Property="Margin" Value="0,0,0,15"/>
        </Style>

        <!-- Label Style -->
        <Style x:Key="Label" TargetType="TextBlock">
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Foreground" Value="{StaticResource TextSecondaryColor}"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="Margin" Value="0,0,10,0"/>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <!-- Professional Header -->
        <Border Grid.Row="0" Background="{StaticResource PrimaryColor}" Padding="25,20">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel Grid.Column="0">
                    <TextBlock Text="Network Bridge Manager" 
                              FontSize="24" FontWeight="Bold" Foreground="White"/>
                    <TextBlock Text="Professional packet interception and forwarding tool" 
                              FontSize="13" Foreground="#BDC3C7" Margin="0,5,0,0"/>
                </StackPanel>

                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                    <Border Background="#34495E" Padding="15,10" CornerRadius="4" Margin="0,0,10,0">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="Computer:" Foreground="#95A5A6" FontSize="12" Margin="0,0,8,0"/>
                            <TextBlock x:Name="ComputerNameDisplay" Text="PC-NAME" 
                                      Foreground="White" FontWeight="SemiBold" FontSize="13"/>
                        </StackPanel>
                    </Border>
                    <Button Content="⚙ Settings" Style="{StaticResource SecondaryButton}" 
                           Width="100" Click="Settings_Click"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Main Content Area -->
        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="25">
            <StackPanel>

                <!-- Physical Interfaces Section -->
                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <Grid Margin="0,0,0,15">
                            <TextBlock Text="Network Interfaces" Style="{StaticResource SectionHeader}"/>
                            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                                <TextBlock Text="Show virtual adapters" 
                                          Style="{StaticResource Label}" 
                                          VerticalAlignment="Center"
                                          Margin="0,0,10,0"/>
                                <CheckBox x:Name="ShowVirtualCheckBox" 
                                         VerticalAlignment="Center"
                                         Checked="ShowVirtual_Changed"
                                         Unchecked="ShowVirtual_Changed"/>
                                <Button Content="🔄 Refresh" 
                                       Style="{StaticResource SecondaryButton}" 
                                       Padding="12,6" 
                                       Margin="15,0,0,0"
                                       Click="RefreshInterfaces_Click"/>
                            </StackPanel>
                        </Grid>

                        <DataGrid x:Name="PhysicalInterfacesDataGrid" 
                                 ItemsSource="{Binding PhysicalInterfaces}"
                                 MaxHeight="300">
                            <DataGrid.Columns>
                                <DataGridCheckBoxColumn Header="Select" Binding="{Binding IsSelected}" Width="60"/>
                                <DataGridTextColumn Header="Name" Binding="{Binding Name}" Width="150"/>
                                <DataGridTextColumn Header="Description" Binding="{Binding Description}" Width="*"/>
                                <DataGridTextColumn Header="Type" Binding="{Binding TypeDisplay}" Width="120"/>
                                <DataGridTextColumn Header="Status" Binding="{Binding StatusDisplay}" Width="100"/>
                                <DataGridTextColumn Header="Speed" Binding="{Binding SpeedDisplay}" Width="100"/>
                                <DataGridTextColumn Header="IP Address" Binding="{Binding IpAddress}" Width="130"/>
                            </DataGrid.Columns>
                        </DataGrid>
                    </StackPanel>
                </Border>

                <!-- Virtual Interfaces Section -->
                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="Virtual Capture Interfaces" Style="{StaticResource SectionHeader}"/>

                        <!-- Create Interface Form -->
                        <Border Background="#FAFAFA" Padding="15" CornerRadius="4" Margin="0,0,0,15">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="200"/>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="150"/>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>

                                <TextBlock Grid.Column="0" Text="Name:" Style="{StaticResource Label}"/>
                                <TextBox Grid.Column="1" x:Name="InterfaceNameTextBox" 
                                        Margin="0,0,15,0"/>

                                <TextBlock Grid.Column="2" Text="Direction:" Style="{StaticResource Label}"/>
                                <ComboBox Grid.Column="3" x:Name="DirectionComboBox" Margin="0,0,15,0">
                                    <ComboBoxItem Content="Input"/>
                                    <ComboBoxItem Content="Output"/>
                                    <ComboBoxItem Content="Bidirectional" IsSelected="True"/>
                                </ComboBox>

                                <TextBlock Grid.Column="4" Text="Filter:" Style="{StaticResource Label}"/>
                                <TextBox Grid.Column="5" x:Name="FilterTextBox" 
                                        Text="tcp or udp" 
                                        ToolTip="WinDivert filter: tcp, udp, tcp.DstPort == 80, etc."
                                        Margin="0,0,15,0"/>

                                <Button Grid.Column="6" Content="+ Create" 
                                       Style="{StaticResource PrimaryButton}" 
                                       Click="CreateInterface_Click"
                                       Padding="15,8"/>
                            </Grid>
                        </Border>

                        <!-- Virtual Interfaces List -->
                        <DataGrid x:Name="VirtualInterfacesDataGrid" 
                                 ItemsSource="{Binding VirtualInterfaces}"
                                 MaxHeight="250">
                            <DataGrid.Columns>
                                <DataGridTextColumn Header="Name" Binding="{Binding Name}" Width="150"/>
                                <DataGridTextColumn Header="Direction" Binding="{Binding Direction}" Width="120"/>
                                <DataGridTextColumn Header="Status" Binding="{Binding StatusDisplay}" Width="90"/>
                                <DataGridTextColumn Header="Packets RX" Binding="{Binding PacketsReceived}" Width="100"/>
                                <DataGridTextColumn Header="Packets TX" Binding="{Binding PacketsSent}" Width="100"/>
                                <DataGridTextColumn Header="Data RX" Binding="{Binding BytesReceivedDisplay}" Width="100"/>
                                <DataGridTextColumn Header="Data TX" Binding="{Binding BytesSentDisplay}" Width="100"/>
                                <DataGridTextColumn Header="Filter" Binding="{Binding Filter}" Width="*"/>
                                <DataGridTemplateColumn Header="Actions" Width="220">
                                    <DataGridTemplateColumn.CellTemplate>
                                        <DataTemplate>
                                            <StackPanel Orientation="Horizontal">
                                                <Button Content="▶ Start" 
                                                       Style="{StaticResource PrimaryButton}"
                                                       Click="StartInterface_Click" 
                                                       Tag="{Binding Id}" 
                                                       Padding="10,5" Margin="2"/>
                                                <Button Content="⏸ Stop" 
                                                       Style="{StaticResource SecondaryButton}"
                                                       Click="StopInterface_Click" 
                                                       Tag="{Binding Id}" 
                                                       Padding="10,5" Margin="2"/>
                                                <Button Content="✖ Delete" 
                                                       Style="{StaticResource DangerButton}"
                                                       Click="DeleteInterface_Click" 
                                                       Tag="{Binding Id}" 
                                                       Padding="10,5" Margin="2"/>
                                            </StackPanel>
                                        </DataTemplate>
                                    </DataGridTemplateColumn.CellTemplate>
                                </DataGridTemplateColumn>
                            </DataGrid.Columns>
                        </DataGrid>
                    </StackPanel>
                </Border>

                <!-- Remote Connections Section -->
                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="Remote Connections" Style="{StaticResource SectionHeader}"/>

                        <!-- Connection Form -->
                        <Border Background="#FAFAFA" Padding="15" CornerRadius="4" Margin="0,0,0,15">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                </Grid.RowDefinitions>

                                <TextBlock Grid.Row="0" Grid.Column="0" Text="Listen Port:" 
                                          Style="{StaticResource Label}"/>
                                <TextBox Grid.Row="0" Grid.Column="1" x:Name="ListenPortTextBox" 
                                        Text="9999" Width="100" HorizontalAlignment="Left" Margin="0,0,15,0"/>
                                <Button Grid.Row="0" Grid.Column="2" Content="▶ Start Listener" 
                                       Style="{StaticResource SuccessButton}" 
                                       Click="StartListener_Click" Margin="0,0,5,0"/>
                                <Button Grid.Row="0" Grid.Column="3" Content="⏸ Stop Listener" 
                                       Style="{StaticResource SecondaryButton}" 
                                       Click="StopListener_Click"/>

                                <TextBlock Grid.Row="1" Grid.Column="0" Text="Remote Host:" 
                                          Style="{StaticResource Label}" Margin="0,10,10,0"/>
                                <StackPanel Grid.Row="1" Grid.Column="1" Orientation="Horizontal" Margin="0,10,0,0">
                                    <TextBox x:Name="RemoteIpTextBox" Text="192.168.1.100" Width="150"/>
                                    <TextBlock Text=":" VerticalAlignment="Center" Margin="10,0"/>
                                    <TextBox x:Name="RemotePortTextBox" Text="9999" Width="80"/>
                                </StackPanel>
                                <Button Grid.Row="1" Grid.Column="2" Grid.ColumnSpan="2" 
                                       Content="→ Connect" 
                                       Style="{StaticResource PrimaryButton}" 
                                       Click="ConnectToRemote_Click" 
                                       Margin="0,10,0,0"
                                       HorizontalAlignment="Right"/>
                            </Grid>
                        </Border>

                        <!-- Remote Hosts List -->
                        <DataGrid x:Name="RemoteHostsDataGrid" 
                                 ItemsSource="{Binding RemoteHosts}"
                                 MaxHeight="200">
                            <DataGrid.Columns>
                                <DataGridTextColumn Header="Host Name" Binding="{Binding DisplayName}" Width="200"/>
                                <DataGridTextColumn Header="IP Address" Binding="{Binding Endpoint.Address}" Width="150"/>
                                <DataGridTextColumn Header="Port" Binding="{Binding Endpoint.Port}" Width="80"/>
                                <DataGridTextColumn Header="Status" Binding="{Binding StatusDisplay}" Width="120"/>
                                <DataGridTextColumn Header="Last Seen" Binding="{Binding LastSeen, StringFormat='{}{0:HH:mm:ss}'}" Width="*"/>
                                <DataGridTemplateColumn Header="Actions" Width="120">
                                    <DataGridTemplateColumn.CellTemplate>
                                        <DataTemplate>
                                            <Button Content="Disconnect" 
                                                   Style="{StaticResource DangerButton}"
                                                   Click="DisconnectRemote_Click" 
                                                   Tag="{Binding HostId}" 
                                                   Padding="10,5"/>
                                        </DataTemplate>
                                    </DataGridTemplateColumn.CellTemplate>
                                </DataGridTemplateColumn>
                            </DataGrid.Columns>
                        </DataGrid>
                    </StackPanel>
                </Border>

                <!-- Interface Wiring Section -->
                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="Interface Routing" Style="{StaticResource SectionHeader}"/>
                        <TextBlock Text="Route traffic between interfaces to create your network topology" 
                                  FontSize="12" 
                                  Foreground="{StaticResource TextSecondaryColor}" 
                                  Margin="0,0,0,15"/>

                        <!-- Wiring Form -->
                        <Border Background="#FAFAFA" Padding="15" CornerRadius="4" Margin="0,0,0,15">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>

                                <TextBlock Grid.Column="0" Text="Source:" Style="{StaticResource Label}"/>
                                <ComboBox Grid.Column="1" x:Name="SourceInterfaceComboBox" 
                                         DisplayMemberPath="Name" 
                                         SelectedValuePath="Id"
                                         Margin="0,0,15,0"/>

                                <TextBlock Grid.Column="2" Text="→ Destination:" Style="{StaticResource Label}"/>
                                <ComboBox Grid.Column="3" x:Name="DestInterfaceComboBox" 
                                         DisplayMemberPath="Name" 
                                         SelectedValuePath="Id"
                                         Margin="0,0,15,0"/>

                                <Button Grid.Column="4" Content="+ Create Route" 
                                       Style="{StaticResource PrimaryButton}" 
                                       Click="CreateWiring_Click"/>
                            </Grid>
                        </Border>

                        <!-- Wiring List -->
                        <DataGrid x:Name="WiringsDataGrid" 
                                 ItemsSource="{Binding Wirings}"
                                 MaxHeight="200">
                            <DataGrid.Columns>
                                <DataGridTextColumn Header="Source Interface" Binding="{Binding SourceName}" Width="*"/>
                                <DataGridTextColumn Header="Destination Interface" Binding="{Binding DestinationName}" Width="*"/>
                                <DataGridTextColumn Header="Type" Binding="{Binding Type}" Width="100"/>
                                <DataGridCheckBoxColumn Header="Enabled" Binding="{Binding IsEnabled}" Width="80"/>
                                <DataGridTemplateColumn Header="Actions" Width="100">
                                    <DataGridTemplateColumn.CellTemplate>
                                        <DataTemplate>
                                            <Button Content="Delete" 
                                                   Style="{StaticResource DangerButton}"
                                                   Click="DeleteWiring_Click" 
                                                   Tag="{Binding Id}" 
                                                   Padding="10,5"/>
                                        </DataTemplate>
                                    </DataGridTemplateColumn.CellTemplate>
                                </DataGridTemplateColumn>
                            </DataGrid.Columns>
                        </DataGrid>
                    </StackPanel>
                </Border>

            </StackPanel>
        </ScrollViewer>
    </Grid>
</Window>
'@
$mainWindowXaml | Out-File "./$uiDir/MainWindow.axaml" -Encoding UTF8
# Create success button style helper
$successButtonStyle = @'
        <Style x:Key="SuccessButton" TargetType="Button" BasedOn="{StaticResource PrimaryButton}">
            <Setter Property="Background" Value="{StaticResource SuccessColor}"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#229954"/>
                </Trigger>
            </Style.Triggers>
        </Style>
'@

Write-Host "[7/8] Creating MainWindow code-behind..." -ForegroundColor Green

# MainWindow.xaml.cs - WITH INTERFACE DISCOVERY
$mainWindowXamlCs = @'
using System;
using System.Collections.ObjectModel;
using System.Linq;
using System.Net;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using NetworkBridge.Core.Interfaces;
using NetworkBridge.Core.Services;
using NetworkBridge.Models;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.DependencyInjection;

namespace NetworkBridge.UI
{
    public partial class MainWindow : Window
    {
        private readonly INetworkBridgeService _bridgeService;
        private readonly IRemoteConnectionService _connectionService;
        private readonly INetworkInterfaceDiscoveryService _discoveryService;
        private readonly ILogger<MainWindow> _logger;
        
        private readonly ObservableCollection<PhysicalNetworkInterface> _physicalInterfaces;
        private readonly ObservableCollection<VirtualInterface> _virtualInterfaces;
        private readonly ObservableCollection<RemoteHost> _remoteHosts;
        private readonly ObservableCollection<InterfaceWiring> _wirings;

        public ObservableCollection<PhysicalNetworkInterface> PhysicalInterfaces => _physicalInterfaces;
        public ObservableCollection<VirtualInterface> VirtualInterfaces => _virtualInterfaces;
        public ObservableCollection<RemoteHost> RemoteHosts => _remoteHosts;
        public ObservableCollection<InterfaceWiring> Wirings => _wirings;

        public MainWindow()
        {
            InitializeComponent();

            var services = new ServiceCollection();
            ConfigureServices(services);
            var serviceProvider = services.BuildServiceProvider();

            _bridgeService = serviceProvider.GetRequiredService<INetworkBridgeService>();
            _connectionService = serviceProvider.GetRequiredService<IRemoteConnectionService>();
            _discoveryService = serviceProvider.GetRequiredService<INetworkInterfaceDiscoveryService>();
            _logger = serviceProvider.GetRequiredService<ILogger<MainWindow>>();

            _physicalInterfaces = new ObservableCollection<PhysicalNetworkInterface>();
            _virtualInterfaces = new ObservableCollection<VirtualInterface>();
            _remoteHosts = new ObservableCollection<RemoteHost>();
            _wirings = new ObservableCollection<InterfaceWiring>();

            DataContext = this;
            ComputerNameDisplay.Text = Environment.MachineName;

            _connectionService.RemoteHostConnected += OnRemoteHostConnected;
            _connectionService.RemoteHostDisconnected += OnRemoteHostDisconnected;

            SourceInterfaceComboBox.ItemsSource = _virtualInterfaces;
            DestInterfaceComboBox.ItemsSource = _virtualInterfaces;

            _logger.LogInformation("Application started");

            // Auto-discover interfaces on startup
            _ = DiscoverInterfacesAsync();
        }

        private void ConfigureServices(IServiceCollection services)
        {
            services.AddLogging(builder =>
            {
                builder.AddConsole();
                builder.SetMinimumLevel(LogLevel.Information);
            });

            services.AddSingleton<INetworkInterfaceDiscoveryService, NetworkInterfaceDiscoveryService>();
            services.AddSingleton<IRemoteConnectionService, RemoteConnectionService>();
            services.AddSingleton<INetworkBridgeService, NetworkBridgeService>();
        }

        private async Task DiscoverInterfacesAsync()
        {
            try
            {
                bool includeVirtual = ShowVirtualCheckBox.IsChecked ?? false;
                var interfaces = await _discoveryService.DiscoverInterfacesAsync(includeVirtual);

                _physicalInterfaces.Clear();
                foreach (var iface in interfaces)
                {
                    _physicalInterfaces.Add(iface);
                }

                _logger.LogInformation("Discovered {Count} network interfaces", interfaces.Count);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to discover interfaces");
                MessageBox.Show($"Failed to discover network interfaces:\n{ex.Message}", "Error", 
                              MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private async void RefreshInterfaces_Click(object sender, RoutedEventArgs e)
        {
            await DiscoverInterfacesAsync();
            MessageBox.Show("Network interfaces refreshed", "Success", 
                          MessageBoxButton.OK, MessageBoxImage.Information);
        }

        private async void ShowVirtual_Changed(object sender, RoutedEventArgs e)
        {
            await DiscoverInterfacesAsync();
        }

        private async void CreateInterface_Click(object sender, RoutedEventArgs e)
        {
            try
            {
                string name = InterfaceNameTextBox.Text;
                if (string.IsNullOrWhiteSpace(name))
                {
                    MessageBox.Show("Please enter an interface name", "Validation", 
                                  MessageBoxButton.OK, MessageBoxImage.Warning);
                    return;
                }

                var directionItem = DirectionComboBox.SelectedItem as ComboBoxItem;
                if (!Enum.TryParse<InterfaceDirection>(directionItem?.Content.ToString(), out var direction))
                {
                    direction = InterfaceDirection.Bidirectional;
                }

                string filter = FilterTextBox.Text;
                if (string.IsNullOrWhiteSpace(filter))
                {
                    filter = "tcp or udp";
                }

                var virtualInterface = await _bridgeService.CreateVirtualInterfaceAsync(name, direction, filter);
                _virtualInterfaces.Add(virtualInterface);

                MessageBox.Show($"Interface '{name}' created successfully", "Success", 
                              MessageBoxButton.OK, MessageBoxImage.Information);

                InterfaceNameTextBox.Clear();
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Failed to create interface: {ex.Message}", "Error", 
                              MessageBoxButton.OK, MessageBoxImage.Error);
                _logger.LogError(ex, "Failed to create interface");
            }
        }

        private async void StartInterface_Click(object sender, RoutedEventArgs e)
        {
            if (sender is Button button && button.Tag is Guid interfaceId)
            {
                try
                {
                    bool success = await _bridgeService.StartInterfaceAsync(interfaceId);
                    if (success)
                    {
                        MessageBox.Show("Interface started successfully", "Success", 
                                      MessageBoxButton.OK, MessageBoxImage.Information);
                    }
                    else
                    {
                        MessageBox.Show("Failed to start interface", "Error", 
                                      MessageBoxButton.OK, MessageBoxImage.Error);
                    }
                }
                catch (Exception ex)
                {
                    MessageBox.Show($"Error starting interface:\n{ex.Message}\n\nMake sure to run as Administrator!", 
                                  "Error", MessageBoxButton.OK, MessageBoxImage.Error);
                    _logger.LogError(ex, "Failed to start interface");
                }
            }
        }

        private async void StopInterface_Click(object sender, RoutedEventArgs e)
        {
            if (sender is Button button && button.Tag is Guid interfaceId)
            {
                try
                {
                    await _bridgeService.StopInterfaceAsync(interfaceId);
                    MessageBox.Show("Interface stopped", "Success", 
                                  MessageBoxButton.OK, MessageBoxImage.Information);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed to stop interface");
                }
            }
        }

        private async void DeleteInterface_Click(object sender, RoutedEventArgs e)
        {
            if (sender is Button button && button.Tag is Guid interfaceId)
            {
                var result = MessageBox.Show("Delete this interface?", "Confirm", 
                                           MessageBoxButton.YesNo, MessageBoxImage.Question);

                if (result == MessageBoxResult.Yes)
                {
                    try
                    {
                        await _bridgeService.DeleteVirtualInterfaceAsync(interfaceId);
                        var interfaceToRemove = _virtualInterfaces.FirstOrDefault(i => i.Id == interfaceId);
                        if (interfaceToRemove != null)
                        {
                            _virtualInterfaces.Remove(interfaceToRemove);
                        }
                    }
                    catch (Exception ex)
                    {
                        _logger.LogError(ex, "Failed to delete interface");
                    }
                }
            }
        }

        private async void StartListener_Click(object sender, RoutedEventArgs e)
        {
            try
            {
                if (!int.TryParse(ListenPortTextBox.Text, out var port))
                {
                    MessageBox.Show("Invalid port number", "Validation", 
                                  MessageBoxButton.OK, MessageBoxImage.Warning);
                    return;
                }

                await _connectionService.StartListeningAsync(port);
                MessageBox.Show($"Listener started on port {port}", "Success", 
                              MessageBoxButton.OK, MessageBoxImage.Information);
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Failed to start listener:\n{ex.Message}", "Error", 
                              MessageBoxButton.OK, MessageBoxImage.Error);
                _logger.LogError(ex, "Failed to start listener");
            }
        }

        private async void StopListener_Click(object sender, RoutedEventArgs e)
        {
            try
            {
                await _connectionService.StopListeningAsync();
                MessageBox.Show("Listener stopped", "Success", 
                              MessageBoxButton.OK, MessageBoxImage.Information);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to stop listener");
            }
        }

        private async void ConnectToRemote_Click(object sender, RoutedEventArgs e)
        {
            try
            {
                if (!IPAddress.TryParse(RemoteIpTextBox.Text, out var ipAddress))
                {
                    MessageBox.Show("Invalid IP address", "Validation", 
                                  MessageBoxButton.OK, MessageBoxImage.Warning);
                    return;
                }

                if (!int.TryParse(RemotePortTextBox.Text, out var port))
                {
                    MessageBox.Show("Invalid port", "Validation", 
                                  MessageBoxButton.OK, MessageBoxImage.Warning);
                    return;
                }

                var endpoint = new IPEndPoint(ipAddress, port);
                bool success = await _connectionService.ConnectToRemoteAsync(endpoint);

                if (success)
                {
                    MessageBox.Show($"Connected to {endpoint}", "Success", 
                                  MessageBoxButton.OK, MessageBoxImage.Information);
                }
                else
                {
                    MessageBox.Show($"Failed to connect to {endpoint}", "Error", 
                                  MessageBoxButton.OK, MessageBoxImage.Error);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Connection error");
            }
        }

        private async void DisconnectRemote_Click(object sender, RoutedEventArgs e)
        {
            if (sender is Button button && button.Tag is Guid hostId)
            {
                try
                {
                    await _connectionService.DisconnectFromRemoteAsync(hostId);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed to disconnect");
                }
            }
        }

        private async void CreateWiring_Click(object sender, RoutedEventArgs e)
        {
            try
            {
                if (SourceInterfaceComboBox.SelectedValue == null || 
                    DestInterfaceComboBox.SelectedValue == null)
                {
                    MessageBox.Show("Please select both source and destination", "Validation", 
                                  MessageBoxButton.OK, MessageBoxImage.Warning);
                    return;
                }

                var sourceId = (Guid)SourceInterfaceComboBox.SelectedValue;
                var destId = (Guid)DestInterfaceComboBox.SelectedValue;

                if (sourceId == destId)
                {
                    MessageBox.Show("Source and destination must be different", "Validation", 
                                  MessageBoxButton.OK, MessageBoxImage.Warning);
                    return;
                }

                var wiring = await _bridgeService.CreateWiringAsync(sourceId, destId, WiringType.Local);
                _wirings.Add(wiring);

                MessageBox.Show("Route created successfully", "Success", 
                              MessageBoxButton.OK, MessageBoxImage.Information);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to create wiring");
            }
        }

        private async void DeleteWiring_Click(object sender, RoutedEventArgs e)
        {
            if (sender is Button button && button.Tag is Guid wiringId)
            {
                try
                {
                    await _bridgeService.DeleteWiringAsync(wiringId);
                    var wiringToRemove = _wirings.FirstOrDefault(w => w.Id == wiringId);
                    if (wiringToRemove != null)
                    {
                        _wirings.Remove(wiringToRemove);
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed to delete wiring");
                }
            }
        }

        private void Settings_Click(object sender, RoutedEventArgs e)
        {
            MessageBox.Show("Settings functionality coming soon", "Info", 
                          MessageBoxButton.OK, MessageBoxImage.Information);
        }

        private void OnRemoteHostConnected(object sender, RemoteHost host)
        {
            Dispatcher.Invoke(() =>
            {
                _remoteHosts.Add(host);
                _logger.LogInformation("Remote host connected: {Name}", host.DisplayName);
            });
        }

        private void OnRemoteHostDisconnected(object sender, RemoteHost host)
        {
            Dispatcher.Invoke(() =>
            {
                var existingHost = _remoteHosts.FirstOrDefault(h => h.HostId == host.HostId);
                if (existingHost != null)
                {
                    _remoteHosts.Remove(existingHost);
                }
            });
        }

        protected override void OnClosed(EventArgs e)
        {
            base.OnClosed(e);
            
            if (_bridgeService is IDisposable disposableBridge)
                disposableBridge.Dispose();
            if (_connectionService is IDisposable disposableConnection)
                disposableConnection.Dispose();
        }
    }
}
'@
$mainWindowXamlCs | Out-File "./$uiDir/MainWindow.xaml.cs" -Encoding UTF8

# App.xaml and App.xaml.cs
$appXaml = @'
<Application x:Class="NetworkBridge.UI.App"
             xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             StartupUri="MainWindow.xaml">
</Application>
'@

$appXaml | Out-File "./$uiDir/App.xaml" -Encoding UTF8

$appXamlCs = @'
using System.Windows;

namespace NetworkBridge.UI
{
    public partial class App : Application
    {
    }
}
'@
$appXamlCs | Out-File "./$uiDir/App.xaml.cs" -Encoding UTF8

# app.manifest
$appManifest = @"
<?xml version="1.0" encoding="utf-8"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <assemblyIdentity version="1.0.0.0" name="$ProjectName.app"/>
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v2">
    <security>
      <requestedPrivileges xmlns="urn:schemas-microsoft-com:asm.v3">
        <requestedExecutionLevel level="requireAdministrator" uiAccess="false" />
      </requestedPrivileges>
    </security>
  </trustInfo>
</assembly>
"@

$appManifest | Out-File "./$uiDir/app.manifestl" -Encoding UTF8

# ============================================================================
# FINALIZATION
# ============================================================================
Write-Host "[8/8] Finalizing project..." -ForegroundColor Green

dotnet sln add "$modelsDir/$ProjectName.Models.csproj" | Out-Null
dotnet sln add "$coreDir/$ProjectName.Core.csproj" | Out-Null
dotnet sln add "$uiDir/$ProjectName.UI.csproj" | Out-Null

# Create README
$readme = @'

# $ProjectName - Professional Edition

Modern network bridge and MITM tool with **automatic interface detection** and professional UI.

## Features

- ✅ **Automatic Network Interface Detection** - Discovers all physical NICs
- ✅ **Virtual/Physical Filtering** - Toggle virtual adapters (VPN, VMware, etc.)
- ✅ **Professional UI** - Clean, intuitive design
- ✅ **Real-time Statistics** - Packet counts and bandwidth monitoring
- ✅ **Remote Bridge Connections** - Connect multiple instances
- ✅ **Flexible Routing** - Wire interfaces for MITM scenarios

## Build

``` bash
dotnet build
Copy-Item lib/WinDivert/* src/$ProjectName.UI/bin/Debug/net8.0-windows/
cd src/$ProjectName.UI
dotnet run
```
'@