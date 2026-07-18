# Verification

## Windows build

- Configured with CMake for Visual Studio 2022 x64.
- Used local vcpkg dependencies from `vcpkg_installed/x64-windows`.
- Added MSVC `/FS` to avoid parallel PDB write failures.
- Built Release successfully.
- Output executable: `bin/Release/luanti.exe`.

## Runtime check

- Staged vcpkg runtime DLLs into `bin/Release`.
- Confirmed `OpenAL32.dll` and other required DLLs are present beside `luanti.exe`.
- Ran a smoke test against `luanti.exe`; the executable exits cleanly.

## Robot programming check

- Spawned the robot programming flow in-game.
- Confirmed the START block runner detects command blocks connected to the right side of START.
- Fixed the missing `robot.b3d` mesh error by rendering the robot as a textured cube using `robot.png`.

See `verification.png` for the in-game verification screenshot.
