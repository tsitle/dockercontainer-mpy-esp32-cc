# MicroPython Firmware Cross-Compiler

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
$ ./build_mpy.sh 1.11 clean

For the ESP32-WROOM32 with 520kB SRAM:
	$ ./build_mpy.sh 1.11 mk-def
For the ESP32-WROVER-B with 520kB SRAM + 4MB SPI-RAM:
	$ ./build_mpy.sh 1.11 mk-spiram
```

The new firmware binary will be copied to  

- ESP32-WROOM32: `./mpy-firmware-1.11-def.bin`
- ESP32-WROVER-B: `./mpy-firmware-1.11-spiram.bin`

If you'd like to compile a different firmware version just replace `1.11` with that version number in the commands above.
