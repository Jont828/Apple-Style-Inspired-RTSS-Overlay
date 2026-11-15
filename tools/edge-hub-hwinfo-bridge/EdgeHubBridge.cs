// Lian Li Edge Hub Advanced -> HWiNFO custom sensor bridge.
//
// Reads the hub's temperatures over USB HID (VID 0x39B0, PID 0x0101) using only the
// read-only commands documented by https://github.com/sgtaziz/lian-li-linux
// (crates/lianli-devices/src/edge_hub.rs) and publishes them as HWiNFO custom sensors:
//   HKCU\Software\HWiNFO64\Sensors\Custom\<sensor name>\TempN  { Name, Value }
// RTSS can then display them through its HWiNFO data source.
//
// Protocol summary:
//   request  (Windows output report, 65 bytes): [0x01, cmd, 0, ...]
//   response (Windows input report, 65 bytes) : [0x00, 0x01, cmd, ..., len_hi @10, len_lo @11, payload @12..]
//   cmd 1 = temperatures, payload: [gpu2_int, gpu2_frac, gpu1_int, gpu1_frac, amb_int, amb_frac,
//                                    gpu2_abnormal, gpu1_abnormal, amb_abnormal]
//           The fractional byte holds decimal digits (e.g. 5 -> .5, 12 -> .12, 125 -> .125).
//   cmd 2 = product info, payload: [type, subtype, fw_major, fw_minor]
//   cmd 5 = serial (ASCII, 12 bytes)

using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using Microsoft.Win32;
using Microsoft.Win32.SafeHandles;

[assembly: System.Reflection.AssemblyTitle("Edge Hub HWiNFO Bridge")]
[assembly: System.Reflection.AssemblyVersion("1.0.0.0")]

namespace EdgeHubBridge
{
    internal sealed class Reading
    {
        public string Name;
        public double? Celsius;
    }

    internal static class Program
    {
        private const ushort Vid = 0x39B0;
        private const ushort Pid = 0x0101;
        private const string RegistryRoot = @"Software\HWiNFO64\Sensors\Custom";
        // Payload order from the hub.
        private static readonly string[] SensorNames = { "GPU 2 Connector", "GPU 1 Connector", "Hub Ambient" };
        // Registry order (Temp0..Temp2). HWiNFO only discovers custom sensors at startup, so the layout is
        // fixed and keys are never deleted while running; unavailable readings are published as 0.
        private static readonly int[] PublishOrder = { 1, 2, 0 };

        private static int Main(string[] args)
        {
            var opts = Options.Parse(args);
            if (opts == null) { PrintUsage(); return 2; }

            if (opts.Remove)
            {
                RemoveSensor(opts.SensorName);
                Log(opts, "Removed HWiNFO custom sensor '" + opts.SensorName + "'.");
                return 0;
            }

            bool createdNew;
            using (var mutex = new Mutex(true, @"Local\EdgeHubHWiNFOBridge", out createdNew))
            {
                if (!createdNew && !opts.Once)
                {
                    Log(opts, "Another instance is already running.");
                    return 1;
                }
                return opts.Once ? RunOnce(opts) : RunLoop(opts);
            }
        }

        private static int RunOnce(Options opts)
        {
            try
            {
                using (var hub = EdgeHub.Open(Vid, Pid))
                {
                    if (opts.Dump) hub.RawReport += r => Console.WriteLine("  <- " + BitConverter.ToString(r));
                    Console.WriteLine("Device : " + hub.DevicePath);
                    Console.WriteLine("Reports: in={0} out={1} bytes", hub.InputLength, hub.OutputLength);
                    byte[] product = hub.Request(2);
                    if (product != null && product.Length >= 4)
                        Console.WriteLine("Product: type={0} subtype={1} firmware={2}.{3:00}", product[0], product[1], product[2], product[3]);
                    byte[] serial = hub.Request(5);
                    if (serial != null)
                        Console.WriteLine("Serial : " + Encoding.ASCII.GetString(serial, 0, Math.Min(12, serial.Length)).Trim('\0', ' '));
                    byte[] payload = hub.Request(1);
                    if (payload == null) { Console.Error.WriteLine("No temperature response from hub."); return 1; }
                    Console.WriteLine("Raw    : " + BitConverter.ToString(payload));
                    var readings = ParseTemperatures(payload);
                    foreach (var r in readings)
                        Console.WriteLine("  {0,-16} {1}", r.Name, r.Celsius.HasValue ? r.Celsius.Value.ToString("0.0##", CultureInfo.InvariantCulture) + " C" : "n/a (sensor not connected/abnormal)");
                    if (!opts.NoRegistry)
                    {
                        Publish(opts, readings);
                        Console.WriteLine("Published to HKCU\\" + RegistryRoot + "\\" + opts.SensorName);
                    }
                    return 0;
                }
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine("Error: " + ex.Message);
                return 1;
            }
        }

        private static int RunLoop(Options opts)
        {
            Log(opts, "Polling Edge Hub every " + opts.IntervalMs + " ms. Ctrl+C to stop.");
            var stop = new ManualResetEvent(false);
            Console.CancelKeyPress += (s, e) => { e.Cancel = true; stop.Set(); };
            SystemEvents.SessionEnding += (s, e) => stop.Set();

            EdgeHub hub = null;
            DateTime lastGood = DateTime.MinValue;
            bool stalePublished = false;
            string lastError = null;
            Publish(opts, null);
            try
            {
                while (!stop.WaitOne(0))
                {
                    try
                    {
                        if (hub == null)
                        {
                            hub = EdgeHub.Open(Vid, Pid);
                            Log(opts, "Connected: " + hub.DevicePath);
                        }
                        byte[] payload = hub.Request(1);
                        if (payload == null) throw new IOException("no temperature response");
                        var readings = ParseTemperatures(payload);
                        Publish(opts, readings);
                        lastGood = DateTime.UtcNow;
                        stalePublished = false;
                        lastError = null;
                        if (opts.Verbose)
                        {
                            var parts = new List<string>();
                            foreach (var r in readings)
                                parts.Add(r.Name + "=" + (r.Celsius.HasValue ? r.Celsius.Value.ToString("0.0#", CultureInfo.InvariantCulture) : "n/a"));
                            Log(opts, string.Join("  ", parts.ToArray()));
                        }
                    }
                    catch (Exception ex)
                    {
                        if (ex.Message != lastError) Log(opts, "Read failed: " + ex.Message);
                        lastError = ex.Message;
                        if (hub != null) { hub.Dispose(); hub = null; }
                        if (!stalePublished && (DateTime.UtcNow - lastGood).TotalMilliseconds > Math.Max(2500, opts.IntervalMs * 3))
                        {
                            Publish(opts, null);
                            stalePublished = true;
                        }
                        stop.WaitOne(Math.Max(opts.IntervalMs, 3000));
                        continue;
                    }
                    stop.WaitOne(opts.IntervalMs);
                }
            }
            finally
            {
                if (hub != null) hub.Dispose();
                try { Publish(opts, null); } catch (Exception) { }
            }
            return 0;
        }

        internal static List<Reading> ParseTemperatures(byte[] payload)
        {
            if (payload.Length < 9) throw new InvalidDataException("truncated temperature payload");
            var list = new List<Reading>();
            for (int i = 0; i < 3; i++)
            {
                int whole = payload[i * 2];
                int fraction = payload[i * 2 + 1];
                double scale = fraction < 10 ? 10.0 : fraction < 100 ? 100.0 : 1000.0;
                bool abnormal = payload[6 + i] != 0;
                list.Add(new Reading { Name = SensorNames[i], Celsius = abnormal ? (double?)null : whole + fraction / scale });
            }
            return list;
        }

        /// <summary>Writes all readings in a fixed layout; null readings (or a null list) are published as 0.</summary>
        private static void Publish(Options opts, List<Reading> readings)
        {
            using (var sensor = Registry.CurrentUser.CreateSubKey(RegistryRoot + @"\" + opts.SensorName))
            {
                for (int slot = 0; slot < PublishOrder.Length; slot++)
                {
                    int index = PublishOrder[slot];
                    double? celsius = readings != null ? readings[index].Celsius : null;
                    using (var k = sensor.CreateSubKey("Temp" + slot))
                    {
                        k.SetValue("Name", SensorNames[index], RegistryValueKind.String);
                        string value = celsius.HasValue ? celsius.Value.ToString("0.0##", CultureInfo.InvariantCulture) : "0";
                        k.SetValue("Value", value, RegistryValueKind.String);
                    }
                }
            }
        }

        private static void RemoveSensor(string sensorName)
        {
            try { Registry.CurrentUser.DeleteSubKeyTree(RegistryRoot + @"\" + sensorName, false); }
            catch (Exception) { }
        }

        private static void Log(Options opts, string message)
        {
            string line = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + message;
            if (opts.LogFile != null)
            {
                try { File.AppendAllText(opts.LogFile, line + Environment.NewLine); } catch (Exception) { }
            }
            try { Console.WriteLine(line); } catch (Exception) { }
        }

        private static void PrintUsage()
        {
            Console.WriteLine(@"EdgeHubBridge - publish Lian Li Edge Hub Advanced temperatures to HWiNFO

Usage: EdgeHubBridge.exe [options]
  --once                Read once, print values (and publish unless --no-registry), then exit
  --interval <ms>       Poll interval (default 1000, min 250)
  --sensor-name <name>  HWiNFO custom sensor name (default ""Lian Li Edge Hub"")
  --no-registry         Do not write to the registry (with --once)
  --remove              Delete the HWiNFO custom sensor from the registry and exit
  --log <file>          Append log lines to a file
  --verbose             Log every reading
  --dump                With --once, print every raw HID input report received");
        }
    }

    internal sealed class Options
    {
        public bool Once, NoRegistry, Remove, Verbose, Dump;
        public int IntervalMs = 1000;
        public string SensorName = "Lian Li Edge Hub";
        public string LogFile;

        public static Options Parse(string[] args)
        {
            var o = new Options();
            for (int i = 0; i < args.Length; i++)
            {
                switch (args[i].ToLowerInvariant())
                {
                    case "--once": o.Once = true; break;
                    case "--no-registry": o.NoRegistry = true; break;
                    case "--remove": o.Remove = true; break;
                    case "--verbose": o.Verbose = true; break;
                    case "--dump": o.Dump = true; break;
                    case "--interval":
                        int ms;
                        if (++i >= args.Length || !int.TryParse(args[i], out ms)) return null;
                        o.IntervalMs = Math.Max(250, ms);
                        break;
                    case "--sensor-name":
                        if (++i >= args.Length || args[i].Trim().Length == 0 || args[i].Contains(@"\")) return null;
                        o.SensorName = args[i].Trim();
                        break;
                    case "--log":
                        if (++i >= args.Length) return null;
                        o.LogFile = args[i];
                        break;
                    default: return null;
                }
            }
            return o;
        }
    }

    internal sealed class EdgeHub : IDisposable
    {
        private const byte Magic = 0x01;
        private readonly SafeFileHandle _writeHandle;
        private readonly SafeFileHandle _readHandle;
        private readonly FileStream _writeStream;
        private readonly FileStream _readStream;
        private readonly BlockingCollection<byte[]> _responses = new BlockingCollection<byte[]>(64);
        private readonly Thread _reader;
        private volatile bool _disposed;

        public string DevicePath { get; private set; }
        public int InputLength { get; private set; }
        public int OutputLength { get; private set; }
        public event Action<byte[]> RawReport;

        private EdgeHub(string path, int inputLength, int outputLength)
        {
            DevicePath = path;
            InputLength = inputLength;
            OutputLength = outputLength;
            // Separate synchronous handles so a blocked read never serializes behind writes.
            _writeHandle = Native.OpenHid(path, Native.GENERIC_READ | Native.GENERIC_WRITE);
            _readHandle = Native.OpenHid(path, Native.GENERIC_READ | Native.GENERIC_WRITE);
            _writeStream = new FileStream(_writeHandle, FileAccess.Write, outputLength, false);
            _readStream = new FileStream(_readHandle, FileAccess.Read, inputLength, false);
            _reader = new Thread(ReadLoop) { IsBackground = true, Name = "edge-hub-reader" };
            _reader.Start();
        }

        public static EdgeHub Open(ushort vid, ushort pid)
        {
            string match = string.Format("vid_{0:x4}&pid_{1:x4}", vid, pid);
            Exception last = null;
            foreach (string path in Native.EnumerateHidPaths())
            {
                if (path.IndexOf(match, StringComparison.OrdinalIgnoreCase) < 0) continue;
                try
                {
                    int inLen, outLen;
                    using (var probe = Native.OpenHid(path, 0))
                        Native.GetReportLengths(probe, out inLen, out outLen);
                    if (inLen < 12 || outLen < 2) continue;
                    return new EdgeHub(path, inLen, outLen);
                }
                catch (Exception ex) { last = ex; }
            }
            throw new IOException("Edge Hub Advanced (VID 39B0, PID 0101) not found" + (last != null ? ": " + last.Message : ""));
        }

        private void ReadLoop()
        {
            var buffer = new byte[InputLength];
            while (!_disposed)
            {
                int n;
                try { n = _readStream.Read(buffer, 0, buffer.Length); }
                catch (Exception) { if (!_disposed) _responses.TryAdd(null); return; }
                if (n <= 0) continue;
                var copy = new byte[n];
                Buffer.BlockCopy(buffer, 0, copy, 0, n);
                var raw = RawReport;
                if (raw != null) raw(copy);
                if (!_responses.TryAdd(copy))
                {
                    byte[] discard;
                    _responses.TryTake(out discard);
                    _responses.TryAdd(copy);
                }
            }
        }

        /// <summary>Sends a read-only request and returns the response payload, or null on timeout.</summary>
        public byte[] Request(byte command, int timeoutMs = 500)
        {
            if (command != 1 && command != 2 && command != 5)
                throw new ArgumentException("only read-only commands 1, 2 and 5 are allowed");

            byte[] stale;
            while (_responses.TryTake(out stale)) { if (stale == null) throw new IOException("device disconnected"); }

            var packet = new byte[OutputLength];
            // Output reports use report ID 1 followed by the command; input reports arrive with report ID 0.
            packet[0] = Magic;
            packet[1] = command;
            _writeStream.Write(packet, 0, packet.Length);
            _writeStream.Flush();

            var deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
            while (true)
            {
                int remaining = (int)(deadline - DateTime.UtcNow).TotalMilliseconds;
                if (remaining <= 0) return null;
                byte[] response;
                if (!_responses.TryTake(out response, remaining)) return null;
                if (response == null) throw new IOException("device disconnected");
                byte[] payload = ParseResponse(response, command);
                // Other software (e.g. L-Connect 3) may be polling too; ignore replies to other commands.
                if (payload != null) return payload;
            }
        }

        /// <summary>Extracts the payload from an input report (with leading report ID 0), or null if it doesn't match.</summary>
        internal static byte[] ParseResponse(byte[] report, byte command)
        {
            const int o = 1;
            if (report.Length < o + 11 || report[0] != 0x00 || report[o] != Magic || report[o + 1] != command) return null;
            int length = (report[o + 9] << 8) | report[o + 10];
            if (length > 54 || o + 11 + length > report.Length) return null;
            var payload = new byte[length];
            Buffer.BlockCopy(report, o + 11, payload, 0, length);
            return payload;
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            Native.CancelIoEx(_readHandle, IntPtr.Zero);
            try { _readStream.Dispose(); } catch (Exception) { }
            try { _writeStream.Dispose(); } catch (Exception) { }
            _reader.Join(1000);
        }
    }

    internal static class Native
    {
        public const uint GENERIC_READ = 0x80000000;
        public const uint GENERIC_WRITE = 0x40000000;
        private const uint FILE_SHARE_READ = 1, FILE_SHARE_WRITE = 2, OPEN_EXISTING = 3;
        private const int DIGCF_PRESENT = 0x2, DIGCF_DEVICEINTERFACE = 0x10;
        private const int HIDP_STATUS_SUCCESS = 0x00110000;

        [StructLayout(LayoutKind.Sequential)]
        private struct SP_DEVICE_INTERFACE_DATA
        {
            public int cbSize;
            public Guid InterfaceClassGuid;
            public int Flags;
            public IntPtr Reserved;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct HIDP_CAPS
        {
            public ushort Usage, UsagePage, InputReportByteLength, OutputReportByteLength, FeatureReportByteLength;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 17)] public ushort[] Reserved;
            public ushort NumberLinkCollectionNodes, NumberInputButtonCaps, NumberInputValueCaps, NumberInputDataIndices,
                NumberOutputButtonCaps, NumberOutputValueCaps, NumberOutputDataIndices,
                NumberFeatureButtonCaps, NumberFeatureValueCaps, NumberFeatureDataIndices;
        }

        [DllImport("hid.dll")] private static extern void HidD_GetHidGuid(out Guid guid);
        [DllImport("hid.dll", SetLastError = true)] private static extern bool HidD_GetPreparsedData(SafeFileHandle h, out IntPtr data);
        [DllImport("hid.dll")] private static extern bool HidD_FreePreparsedData(IntPtr data);
        [DllImport("hid.dll")] private static extern int HidP_GetCaps(IntPtr data, ref HIDP_CAPS caps);

        [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr SetupDiGetClassDevs(ref Guid guid, IntPtr enumerator, IntPtr hwnd, int flags);
        [DllImport("setupapi.dll", SetLastError = true)]
        private static extern bool SetupDiEnumDeviceInterfaces(IntPtr set, IntPtr info, ref Guid guid, int index, ref SP_DEVICE_INTERFACE_DATA data);
        [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr set, ref SP_DEVICE_INTERFACE_DATA data, IntPtr detail, int size, out int required, IntPtr info);
        [DllImport("setupapi.dll")] private static extern bool SetupDiDestroyDeviceInfoList(IntPtr set);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr sa, uint disposition, uint flags, IntPtr template);
        [DllImport("kernel32.dll")] public static extern bool CancelIoEx(SafeFileHandle h, IntPtr overlapped);

        public static IEnumerable<string> EnumerateHidPaths()
        {
            Guid guid;
            HidD_GetHidGuid(out guid);
            IntPtr set = SetupDiGetClassDevs(ref guid, IntPtr.Zero, IntPtr.Zero, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
            if (set == new IntPtr(-1)) yield break;
            try
            {
                for (int i = 0; ; i++)
                {
                    var data = new SP_DEVICE_INTERFACE_DATA { cbSize = Marshal.SizeOf(typeof(SP_DEVICE_INTERFACE_DATA)) };
                    if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref guid, i, ref data)) break;
                    int required;
                    SetupDiGetDeviceInterfaceDetail(set, ref data, IntPtr.Zero, 0, out required, IntPtr.Zero);
                    if (required <= 0) continue;
                    IntPtr detail = Marshal.AllocHGlobal(required);
                    try
                    {
                        Marshal.WriteInt32(detail, IntPtr.Size == 8 ? 8 : 6);
                        if (!SetupDiGetDeviceInterfaceDetail(set, ref data, detail, required, out required, IntPtr.Zero)) continue;
                        yield return Marshal.PtrToStringUni(new IntPtr(detail.ToInt64() + 4));
                    }
                    finally { Marshal.FreeHGlobal(detail); }
                }
            }
            finally { SetupDiDestroyDeviceInfoList(set); }
        }

        public static SafeFileHandle OpenHid(string path, uint access)
        {
            var h = CreateFile(path, access, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
            if (h.IsInvalid) throw new IOException("cannot open HID device (Win32 error " + Marshal.GetLastWin32Error() + ")");
            return h;
        }

        public static void GetReportLengths(SafeFileHandle h, out int input, out int output)
        {
            IntPtr pre;
            if (!HidD_GetPreparsedData(h, out pre)) throw new IOException("HidD_GetPreparsedData failed");
            try
            {
                var caps = new HIDP_CAPS();
                if (HidP_GetCaps(pre, ref caps) != HIDP_STATUS_SUCCESS) throw new IOException("HidP_GetCaps failed");
                input = caps.InputReportByteLength;
                output = caps.OutputReportByteLength;
            }
            finally { HidD_FreePreparsedData(pre); }
        }
    }
}
