# MicroPython ESP32 Firmware Cross-Compiler using a Docker Image for AMD64

The `mpscripts/` folder is for Python code that will be 'baked-in'
to the firmware but not frozen into more efficient and smaller code.  
Everything in the `mpscripts/` folder is just stored as the raw
Python code in the board's flash memory.  
This saves you from having to copy that code onto the board's filesystem, but doesn't save a lot of memory or processing time.

The `mods/` folder is for Python code that will be frozen into more efficient bytecode.  
This is where you want to place scripts that you'd like freeze to save memory.

## Docker Container usage
First copy your custom MicroPython modules to `./mods/`.  
Then run the following commands:

```
Optional:
	$ ./build_mpy.sh <VERSION> clean def
	or
	$ ./build_mpy.sh <VERSION> clean spiram

For the ESP32-WROOM32 with 520kB SRAM:
	$ ./build_mpy.sh <VERSION> mk def
For the ESP32-WROVER-B with 520kB SRAM + 4MB SPI-RAM:
	$ ./build_mpy.sh <VERSION> mk spiram
```

The new firmware binary will be copied to  

- ESP32-WROOM32: `./mpy-firmware-<VERSION>-def.bin`
- ESP32-WROVER-B: `./mpy-firmware-<VERSION>-spiram.bin`

Currently the MicroPython versions

- 1.11 and
- 1.12 and
- 1.13

are available.
