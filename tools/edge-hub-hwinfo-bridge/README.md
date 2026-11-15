# Edge Hub HWiNFO Bridge

Shows the **Lian Li Edge Hub Advanced** GPU power-connector temperatures in HWiNFO, and therefore in the RTSS overlay.

The hub (USB `39B0:0101`) is only read by L-Connect 3. This helper polls it over USB HID using the read-only commands
reverse-engineered by [sgtaziz/lian-li-linux](https://github.com/sgtaziz/lian-li-linux)
(`crates/lianli-devices/src/edge_hub.rs`) and publishes the values as an
[HWiNFO custom sensor](https://www.hwinfo.com/forum/threads/custom-user-sensors-in-hwinfo.5817/):

| HWiNFO sensor `Lian Li Edge Hub` | Source |
| --- | --- |
| `GPU 1 Connector` (Temp0) | probe on GPU connector 1 |
| `Hub Ambient` (Temp1) | sensor on the hub |
| `GPU 2 Connector` (Temp2) | probe on GPU connector 2 |

Unplugged probes, missing hubs and a stopped bridge read **0**. It runs alongside L-Connect 3 and never sends fan, RGB or
firmware commands.

## Build

No SDK needed — uses the .NET Framework C# compiler that ships with Windows:

```cmd
build.cmd
```

Produces `bin\EdgeHubBridge.exe` (console) and `bin\EdgeHubBridgeHidden.exe` (no window, for startup).

## Test

```cmd
bin\EdgeHubBridge.exe --once --no-registry
```

Add `--dump` to print raw HID reports. Run `bin\EdgeHubBridge.exe --verbose` to poll continuously in a console.

## Run at logon

```powershell
powershell -ExecutionPolicy Bypass -File install-startup.ps1
```

Then **restart HWiNFO once** — it only discovers new custom sensors at startup. Logs go to
`%LOCALAPPDATA%\EdgeHubBridge\bridge.log`. Undo with `uninstall-startup.ps1`.

## Show it in RTSS

HWiNFO must have **Shared Memory Support** enabled (Settings → General). In RTSS **OverlayEditor**, open
**Data sources → Add → HWiNFO64**, pick **Lian Li Edge Hub → GPU 1 Connector**, then reference that source in a layer
like any other HWiNFO value.

## Options

```
--once                Read once, print values (and publish unless --no-registry), then exit
--interval <ms>       Poll interval (default 1000, min 250)
--sensor-name <name>  HWiNFO custom sensor name (default "Lian Li Edge Hub")
--no-registry         Do not write to the registry (with --once)
--remove              Delete the HWiNFO custom sensor from the registry and exit
--log <file>          Append log lines to a file
--verbose             Log every reading
--dump                With --once, print every raw HID input report received
```
